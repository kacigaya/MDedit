#!/usr/bin/env swift
// Draws MdEdit's app icon and the markdown document icon, and writes
// Resources/AppIcon.icns and Resources/MarkdownDocument.icns.
// Run with: swift Scripts/make-icon.swift

import AppKit
import Foundation

/// The app icon: a page with a heading and text lines, crossed by a pencil, on a
/// teal-to-blue squircle. Mirrors docs/logos/logo-3-page-pencil.svg, drawn in its
/// 512-unit coordinate space (y down) and scaled onto a 1024 canvas with the
/// usual macOS breathing room.
func drawIcon(size: CGFloat) -> NSImage {
    // Drawn into an sRGB bitmap so the gradient keeps its colors instead of
    // being converted through the display profile.
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return NSImage() }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer {
        NSGraphicsContext.restoreGraphicsState()
    }

    let unit = size / 1024
    let scale = 824 * unit / 512
    let flip = NSAffineTransform()
    flip.translateX(by: 100 * unit, yBy: 924 * unit)
    flip.scaleX(by: scale, yBy: -scale)
    flip.concat()

    func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    }
    func hex(_ value: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    let plate = rounded(0, 0, 512, 512, 115)
    NSGraphicsContext.saveGraphicsState()
    plate.addClip()
    NSGradient(starting: hex(0x14B8A6), ending: hex(0x0369A1))?
        .draw(from: NSPoint(x: 0, y: 0), to: NSPoint(x: 512, y: 512), options: [])
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.setFill()
    rounded(120, 86, 250, 330, 30).fill()
    hex(0x0F766E).setFill()
    rounded(160, 136, 110, 30, 15).fill()
    hex(0xCBD5E1).setFill()
    for (y, w) in [(196, 170), (232, 150), (268, 170), (304, 90)] as [(CGFloat, CGFloat)] {
        rounded(160, y, w, 16, 8).fill()
    }

    // The pencil, drawn along +x and then turned to point down-left.
    let pencil = NSAffineTransform()
    pencil.translateX(by: 410, yBy: 290)
    pencil.rotate(byDegrees: 135)
    pencil.concat()

    func shape(_ path: NSBezierPath, fill: NSColor) {
        fill.setFill()
        path.fill()
        NSColor.white.setStroke()
        path.lineWidth = 12
        path.lineJoinStyle = .round
        path.stroke()
    }
    shape(rounded(-34, -24, 34, 48, 8), fill: hex(0xFDA4AF))
    shape(NSBezierPath(rect: NSRect(x: 0, y: -24, width: 150, height: 48)), fill: hex(0xFBBF24))
    let tip = NSBezierPath()
    tip.move(to: NSPoint(x: 150, y: -24))
    tip.line(to: NSPoint(x: 205, y: 0))
    tip.line(to: NSPoint(x: 150, y: 24))
    tip.close()
    shape(tip, fill: hex(0xFDE68A))
    let lead = NSBezierPath()
    lead.move(to: NSPoint(x: 190, y: -7))
    lead.line(to: NSPoint(x: 205, y: 0))
    lead.line(to: NSPoint(x: 190, y: 7))
    lead.close()
    hex(0x334155).setFill()
    lead.fill()

    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(rep)
    return image
}

/// The markdown mark in a rectangle 564 by 364 units of a 1024 icon.
func drawMark(in markRect: NSRect, unit: CGFloat, color: NSColor) {
    let mark = NSBezierPath(roundedRect: markRect, xRadius: 46 * unit, yRadius: 46 * unit)
    mark.lineWidth = 40 * unit
    color.setStroke()
    mark.stroke()

    let inset = markRect.insetBy(dx: 96 * unit, dy: 78 * unit)
    color.setFill()

    // "M" as three strokes.
    let m = NSBezierPath()
    m.move(to: NSPoint(x: inset.minX, y: inset.minY))
    m.line(to: NSPoint(x: inset.minX, y: inset.maxY))
    m.line(to: NSPoint(x: inset.minX + inset.width * 0.22, y: inset.maxY))
    m.line(to: NSPoint(x: inset.minX + inset.width * 0.36, y: inset.midY + inset.height * 0.08))
    m.line(to: NSPoint(x: inset.minX + inset.width * 0.50, y: inset.maxY))
    m.line(to: NSPoint(x: inset.minX + inset.width * 0.72, y: inset.maxY))
    m.line(to: NSPoint(x: inset.minX + inset.width * 0.72, y: inset.minY))
    m.line(to: NSPoint(x: inset.minX + inset.width * 0.50, y: inset.minY))
    m.line(to: NSPoint(x: inset.minX + inset.width * 0.50, y: inset.midY - inset.height * 0.10))
    m.line(to: NSPoint(x: inset.minX + inset.width * 0.36, y: inset.minY + inset.height * 0.22))
    m.line(to: NSPoint(x: inset.minX + inset.width * 0.22, y: inset.midY - inset.height * 0.10))
    m.line(to: NSPoint(x: inset.minX + inset.width * 0.22, y: inset.minY))
    m.close()
    m.fill()

    // The arrow.
    let arrowX = inset.minX + inset.width * 0.88
    let stem = NSRect(
        x: arrowX - 22 * unit,
        y: inset.minY + inset.height * 0.34,
        width: 44 * unit,
        height: inset.height * 0.66
    )
    NSBezierPath(rect: stem).fill()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: arrowX - 78 * unit, y: inset.minY + inset.height * 0.40))
    head.line(to: NSPoint(x: arrowX + 78 * unit, y: inset.minY + inset.height * 0.40))
    head.line(to: NSPoint(x: arrowX, y: inset.minY))
    head.close()
    head.fill()
}

/// A markdown file: a white page with a folded corner, carrying the mark in
/// the app's blue.
func drawDocumentIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let unit = size / 1024
    let page = NSRect(x: 196 * unit, y: 80 * unit, width: 632 * unit, height: 864 * unit)
    let fold = 180 * unit

    let outline = NSBezierPath()
    outline.move(to: NSPoint(x: page.minX, y: page.minY))
    outline.line(to: NSPoint(x: page.maxX, y: page.minY))
    outline.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    outline.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    outline.line(to: NSPoint(x: page.minX, y: page.maxY))
    outline.close()

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.25)
    shadow.shadowBlurRadius = 18 * unit
    shadow.shadowOffset = NSSize(width: 0, height: -6 * unit)
    shadow.set()
    NSColor.white.setFill()
    outline.fill()
    NSGraphicsContext.restoreGraphicsState()

    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    corner.line(to: NSPoint(x: page.maxX - fold, y: page.maxY - fold))
    corner.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    corner.close()
    NSColor(white: 0.86, alpha: 1).setFill()
    corner.fill()

    let blue = NSColor(calibratedRed: 0.28, green: 0.42, blue: 0.88, alpha: 1)
    let markWidth = page.width - 180 * unit
    let markRect = NSRect(x: page.midX - markWidth / 2, y: page.minY + 170 * unit, width: markWidth, height: markWidth * 364 / 564)
    drawMark(in: markRect, unit: unit * markWidth / (564 * unit), color: blue)
    return image
}

let root = URL(fileURLWithPath: CommandLine.arguments.first.map {
    URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path
} ?? ".")
/// Writes every size of an icon into an .icns file.
func writeIcns(_ draw: (CGFloat) -> NSImage, name: String) throws {
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    for (size, file) in [
        (16, "icon_16x16"), (32, "icon_16x16@2x"),
        (32, "icon_32x32"), (64, "icon_32x32@2x"),
        (128, "icon_128x128"), (256, "icon_128x128@2x"),
        (256, "icon_256x256"), (512, "icon_256x256@2x"),
        (512, "icon_512x512"), (1024, "icon_512x512@2x"),
    ] {
        let image = draw(CGFloat(size))
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { continue }
        try png.write(to: iconset.appendingPathComponent("\(file).png"))
    }

    let output = root.appendingPathComponent("Resources/\(name).icns")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
    try process.run()
    process.waitUntilExit()
    print(process.terminationStatus == 0 ? "wrote \(output.path)" : "iconutil failed for \(name)")
}

try writeIcns(drawIcon, name: "AppIcon")
try writeIcns(drawDocumentIcon, name: "MarkdownDocument")
