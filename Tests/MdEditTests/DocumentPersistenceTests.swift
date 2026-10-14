import AppKit
import Testing
@testable import MdEdit

@Suite("FileFormat")
struct FileFormatTests {
    @Test("Plain UTF-8 with LF round-trips unchanged")
    func utf8RoundTrip() throws {
        let data = Data("# Title\n\nbody\n".utf8)
        let (text, format) = try FileFormat.decode(data)
        #expect(text == "# Title\n\nbody\n")
        #expect(format == FileFormat())
        #expect(try format.encode(text) == data)
    }

    @Test("CRLF is edited as LF and written back as CRLF")
    func crlfRoundTrip() throws {
        let data = Data("a\r\nb\r\n".utf8)
        let (text, format) = try FileFormat.decode(data)
        #expect(text == "a\nb\n")
        #expect(format.lineEnding == "\r\n")
        #expect(try format.encode(text + "c\n") == Data("a\r\nb\r\nc\r\n".utf8))
    }

    @Test("A UTF-8 byte order mark is hidden from the editor and kept on save")
    func bomRoundTrip() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("hello".utf8)
        let (text, format) = try FileFormat.decode(data)
        #expect(text == "hello")
        #expect(format.hasByteOrderMark)
        #expect(try format.encode(text) == data)
    }

    @Test("A non-UTF-8 file is saved in its original encoding")
    func legacyEncodingRoundTrip() throws {
        let data = try #require("café crème".data(using: .isoLatin1))
        let (text, format) = try FileFormat.decode(data)
        #expect(text == "café crème")
        #expect(format.encoding != .utf8)
        #expect(try format.encode(text) == data)
    }

    @Test("Text the original encoding cannot hold is an error, not a silent conversion")
    func unencodableTextThrows() {
        let format = FileFormat(encoding: .ascii)
        #expect(throws: (any Error).self) { try format.encode("naïve") }
    }

    /// A lone `\r` ended a line for the text view but not for the parser,
    /// so styling and line numbers disagreed with what showed.
    @Test("Classic Mac line endings are edited as LF and written back as CR")
    func carriageReturns() throws {
        let data = Data("# A\r# B\r\rtext\r".utf8)
        let (text, format) = try FileFormat.decode(data)
        #expect(text == "# A\n# B\n\ntext\n")
        #expect(format.lineEnding == "\r")
        #expect(try format.encode(text) == data)
        #expect(try FileFormat.decode(Data("a\r\nb\rc\n".utf8)).text == "a\nb\nc\n")
    }

    /// A stray byte in UTF-8 text was read with a lossy guess: stand-ins for
    /// what it could not read, written over the original bytes on save.
    @Test("A file that is not valid UTF-8 is read in an encoding that keeps every byte")
    func strayByteRoundTrip() throws {
        let data = Data("café ".utf8) + Data([0xFF, 0x81]) + Data(" fin\n".utf8)
        let (text, format) = try FileFormat.decode(data)
        #expect(format.encoding != .utf8)
        #expect(try format.encode(text) == data)
    }
}

@Suite("RecoveryStore")
struct RecoveryStoreTests {
    private func store() -> RecoveryStore {
        RecoveryStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("MdEditRecoveryTests-\(UUID().uuidString)", isDirectory: true))
    }

    @Test("Snapshots are written, replaced, removed and cleared")
    func lifecycle() throws {
        let store = store()
        defer { store.removeAll() }
        #expect(store.snapshots().isEmpty)

        let untitled = RecoveryStore.Snapshot(id: UUID(), url: nil, text: "draft")
        var named = RecoveryStore.Snapshot(id: UUID(), url: URL(fileURLWithPath: "/tmp/a.md"), text: "one")
        try store.write(untitled)
        try store.write(named)
        named.text = "two"
        try store.write(named)

        let all = store.snapshots()
        #expect(all.count == 2)
        #expect(all.contains(untitled))
        #expect(all.contains(named))

        store.remove(id: untitled.id)
        #expect(store.snapshots() == [named])

        store.removeAll()
        #expect(store.snapshots().isEmpty)
    }
}

@Suite("Session")
struct SessionTests {
    @Test("A session survives a round trip through user defaults")
    func roundTrip() throws {
        let suite = "MdEditSessionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(Session.load(from: defaults) == nil)
        let session = Session(windows: [
            .init(tabs: [.init(url: URL(fileURLWithPath: "/tmp/a.md"), selectedLocation: 12)], selectedIndex: 0,
                  workspace: URL(fileURLWithPath: "/tmp", isDirectory: true), frame: "10 20 800 600 0 0 1512 949 "),
            .init(tabs: [], selectedIndex: 0),
        ])
        session.save(to: defaults)
        #expect(Session.load(from: defaults) == session)
    }

    @Test("A session saved before multiple windows loads as one window")
    func legacyFormat() throws {
        let legacy = Data(#"{"tabs":[{"url":"file:///tmp/a.md","selectedLocation":3}],"selectedIndex":0}"#.utf8)
        let session = try JSONDecoder().decode(Session.self, from: legacy)
        #expect(session.windows.count == 1)
        #expect(session.windows[0].tabs.map(\.selectedLocation) == [3])
        #expect(session.windows[0].workspace == nil)
    }
}

@MainActor
@Suite("Document")
struct DocumentTests {
    @Test("Recovered text counts as unsaved; saving clears it")
    func restoredTextIsDirty() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MdEditDocTest-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("saved\r\n".utf8).write(to: url)

        let document = try await Document.open(contentsOf: url, theme: .light)
        #expect(!document.isDirty)
        document.restoreUnsavedText("recovered\n")
        #expect(document.isDirty)

        try document.save()
        #expect(!document.isDirty)
        #expect(try Data(contentsOf: url) == Data("recovered\r\n".utf8))
    }

    /// Files were read on the main thread, so one still downloading from
    /// iCloud, or on a slow volume, froze the app until it arrived.
    @Test("A file is read off the main thread, which stays free meanwhile")
    func readOffMainThread() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MdEditDocTest-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        try "# Slow\n".write(to: url, atomically: true, encoding: .utf8)
        let gate = SlowGate()
        let reading = Task {
            try await FileFormat.read(url) { url in
                gate.pass()
                return try Data(contentsOf: url)
            }
        }
        try await gate.waitForReads()
        gate.open()
        #expect(try await reading.value.text == "# Slow\n")
        #expect(gate.calls == 1)
        #expect(!gate.ranOnMainThread)
        #expect(!gate.gaveUp)
    }

    @Test("A document whose file vanished stays dirty until saved")
    func missingFileIsDirty() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MdEditDocTest-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        let document = Document(url: url, text: "x", theme: .light)
        #expect(!document.isDirty)
        document.markMissingOnDisk()
        #expect(document.isDirty)
        try document.save()
        #expect(!document.isDirty)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@MainActor
@Suite("Reverting")
struct RevertTests {
    /// A sync or a checkout rewrites files as they were; reloading those
    /// would restyle the whole document for nothing.
    @Test("A file rewritten unchanged is not reloaded; a changed one is")
    func unchangedRewrite() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MdEditRevert-\(UUID().uuidString).md")
        try "# Notes\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try await Document.open(contentsOf: url, theme: .light)
        let generation = document.storage.editGeneration

        try "# Notes\n".write(to: url, atomically: true, encoding: .utf8)
        try await document.revert()
        #expect(document.storage.editGeneration == generation)

        try "# Changed\n".write(to: url, atomically: true, encoding: .utf8)
        try await document.revert()
        #expect(document.text == "# Changed\n")
        #expect(!document.isDirty)
    }


    /// Reading now happens while the editor stays usable: what is typed
    /// meanwhile must not be replaced by the file's text once it arrives.
    @Test("Edits typed while the file is read again are kept")
    func revertKeepsEditsTypedMeanwhile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MdEditRevert-\(UUID().uuidString).md")
        try "# Notes\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try await Document.open(contentsOf: url, theme: .light)
        try "# Changed\n".write(to: url, atomically: true, encoding: .utf8)

        let gate = SlowGate()
        let reverting = Task {
            try await document.revert { url in
                gate.pass()
                return try Data(contentsOf: url)
            }
        }
        try await gate.waitForReads()
        document.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "typed ")
        gate.open()
        #expect(try await reverting.value == false)
        #expect(document.text == "typed # Notes\n")
        #expect(!gate.ranOnMainThread)
        #expect(!gate.gaveUp)
    }

    /// The history was of the text before the reload; undoing it afterwards
    /// replayed its ranges onto the new text, past its end.
    @Test("Reloading from disk clears the undo history, so Undo cannot crash")
    func revertClearsUndo() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MdEditRevert-\(UUID().uuidString).md")
        try "A line of text long enough to type after.\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try await Document.open(contentsOf: url, theme: .light)
        let editor = EditorViewController(textStorage: document.storage, undoManager: document.undoManager)
        _ = editor.view
        document.undoManager.groupsByEvent = false
        editor.textView.setSelectedRange(NSRange(location: 42, length: 0))
        document.undoManager.beginUndoGrouping()
        editor.textView.insertText(" More typed text.", replacementRange: editor.textView.selectedRange())
        document.undoManager.endUndoGrouping()
        try document.save()

        try "Hi\n".write(to: url, atomically: true, encoding: .utf8)
        try await document.revert()
        #expect(!document.undoManager.canUndo)
        document.undoManager.undo()
        #expect(document.text == "Hi\n")
    }
}

@MainActor
@Suite("Watching and writing files", .serialized)
struct FileOnDiskTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MdEditFiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A save through a symlink renamed a new file over the link, so the
    /// note it pointed to was never updated.
    @Test("Saving a symlinked note writes the file it points to and keeps the link")
    func saveThroughSymlink() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appendingPathComponent("real.md")
        let link = folder.appendingPathComponent("link.md")
        try "old\n".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let document = try await Document.open(contentsOf: link, theme: .light)
        document.storage.replaceCharacters(in: NSRange(location: 0, length: 3), with: "new")
        try document.save()
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
        #expect(try String(contentsOf: target, encoding: .utf8) == "new\n")
    }

    /// The watch looked for a replaced file once, a tenth of a second on;
    /// a file back any later went unwatched, and saving overwrote whatever
    /// was written to it after.
    @Test("A file deleted and recreated a moment later is still watched")
    func watchSurvivesSlowReplace() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("watched.md")
        try "one\n".write(to: url, atomically: false, encoding: .utf8)
        final class Box { var changes = 0 }
        let box = Box()
        let watcher = try #require(FileWatcher(url: url) { box.changes += 1 })

        try FileManager.default.removeItem(at: url)
        try await Task.sleep(for: .milliseconds(500))
        try "two\n".write(to: url, atomically: false, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(400))
        let before = box.changes
        try "three\n".write(to: url, atomically: false, encoding: .utf8)
        for _ in 0..<30 where box.changes == before {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(box.changes > before)
        withExtendedLifetime(watcher) {}
    }
}
