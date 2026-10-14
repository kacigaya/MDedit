import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MdEdit

@Suite("Image cache")
struct ImageCacheTests {
    /// An image file's data: pixels, a resolution, and an EXIF orientation.
    private func imageData(width: Int, height: Int, type: UTType = .png, dpi: Double = 72, orientation: Int = 1) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi, kCGImagePropertyOrientation: orientation,
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("Decoded images keep the size NSImage gives them", arguments: [
        (UTType.png, 72.0), (UTType.png, 144.0), (UTType.jpeg, 72.0), (UTType.jpeg, 300.0),
    ])
    func sizeMatchesNSImage(type: UTType, dpi: Double) throws {
        let data = try imageData(width: 600, height: 400, type: type, dpi: dpi)
        let decoded = try #require(ImageCache.decoded(data))
        let reference = try #require(NSImage(data: data))
        #expect(decoded.size == reference.size)
        #expect(decoded.representations.first?.pixelsWide == 600)
    }

    @Test("A large image is decoded at most as wide as the widest column needs")
    func largeImagesShrink() throws {
        let decoded = try #require(ImageCache.decoded(imageData(width: 4000, height: 3000, type: .jpeg)))
        #expect(decoded.size == NSSize(width: 4000, height: 3000))
        #expect(decoded.representations.first?.pixelsWide == ImageCache.maxPixelWidth)
        #expect(decoded.representations.first?.pixelsHigh == 2100)

        // A tall, narrow image is under the width already: it keeps every pixel.
        let tall = try #require(ImageCache.decoded(imageData(width: 1000, height: 8000)))
        #expect(tall.representations.first?.pixelsWide == 1000)
        #expect(tall.representations.first?.pixelsHigh == 8000)
    }

    @Test("A photo taken sideways is decoded upright")
    func orientation() throws {
        let decoded = try #require(ImageCache.decoded(imageData(width: 600, height: 400, type: .jpeg, orientation: 6)))
        #expect(decoded.size == NSSize(width: 400, height: 600))
        #expect(decoded.representations.first?.pixelsWide == 400)
    }

    @Test("What ImageIO cannot read as a bitmap is left to NSImage")
    func vectorFallsBack() {
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>"#.utf8)
        #expect(ImageCache.decoded(svg) == nil)
    }

    /// `![](/dev/zero)` read forever, and a pipe waited forever for a writer.
    @Test("Only a regular local file within the size limit is read as an image")
    func localFilesOnly() throws {
        #expect(ImageCache.localData(URL(fileURLWithPath: "/dev/zero")) == nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MdEditImages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pipe = directory.appendingPathComponent("pipe.png")
        #expect(mkfifo(pipe.path, 0o600) == 0)
        #expect(ImageCache.localData(pipe) == nil)
        let small = directory.appendingPathComponent("small.png")
        try Data([1, 2, 3]).write(to: small)
        #expect(ImageCache.localData(small) == Data([1, 2, 3]))
        let large = directory.appendingPathComponent("large.png")
        #expect(FileManager.default.createFile(atPath: large.path, contents: nil))
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(ImageCache.maxDownloadBytes + 1))
        try handle.close()
        #expect(ImageCache.localData(large) == nil)
    }
}
