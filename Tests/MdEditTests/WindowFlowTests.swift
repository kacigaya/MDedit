import AppKit
import Testing
@testable import MarkdownKit
@testable import MdEdit

/// Window-level flows: reviewing unsaved tabs before closing or quitting,
/// and tearing a tab off into a window of its own.
@MainActor
@Suite("Window flows", .serialized)
struct WindowFlowTests {
    private let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("MdEditWindowFlows-\(UUID().uuidString)")

    private func makeWindow() -> MainWindowController {
        let controller = MainWindowController()
        controller.recovery = RecoveryStore(directory: scratch.appendingPathComponent("Recovery"))
        return controller
    }

    /// A saved file with unsaved edits, open in a window.
    private func openEdited(_ name: String, in controller: MainWindowController) throws -> Document {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let url = scratch.appendingPathComponent(name)
        try "saved\n".write(to: url, atomically: true, encoding: .utf8)
        controller.open(url: url)
        let document = try #require(controller.documents.first { $0.url == url })
        document.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "edited ")
        #expect(document.isDirty)
        return document
    }

    /// Answers each save prompt in turn, recording which document was asked about.
    private func script(_ controller: MainWindowController, _ answers: [MainWindowController.UnsavedAnswer]) -> () -> [String] {
        var remaining = answers
        var asked: [String] = []
        controller.askAboutUnsaved = { document, answer in
            asked.append(document.displayName)
            answer(remaining.isEmpty ? .cancel : remaining.removeFirst())
        }
        return { asked }
    }

    @Test("Closing an unsaved tab asks; Cancel keeps it, Don’t Save closes it")
    func closeTab() throws {
        let controller = makeWindow()
        controller.newDocument()
        let document = try openEdited("close.md", in: controller)
        let count = controller.documents.count
        let index = try #require(controller.documents.firstIndex { $0 === document })

        let asked = script(controller, [.cancel, .discard])
        controller.closeDocument(at: index)
        #expect(controller.documents.count == count)
        controller.closeDocument(at: index)
        #expect(controller.documents.count == count - 1)
        #expect(asked() == ["close.md", "close.md"])
        // Not saved: the file still holds the old text.
        #expect(try String(contentsOf: document.url!, encoding: .utf8) == "saved\n")
    }

    @Test("Save in the prompt writes the file before the tab goes")
    func saveOnClose() throws {
        let controller = makeWindow()
        controller.newDocument()
        let document = try openEdited("save.md", in: controller)
        _ = script(controller, [.save])
        controller.closeDocument(at: try #require(controller.documents.firstIndex { $0 === document }))
        #expect(!controller.documents.contains { $0 === document })
        #expect(try String(contentsOf: document.url!, encoding: .utf8) == "edited saved\n")
    }

    @Test("Quitting reviews every window in turn and stops at the first Cancel")
    func quitReview() throws {
        let first = makeWindow(), second = makeWindow()
        _ = try openEdited("one.md", in: first)
        _ = try openEdited("two.md", in: second)
        let clean = makeWindow()
        clean.newDocument()

        let askedFirst = script(first, [.discard])
        let askedSecond = script(second, [.cancel])
        var result: Bool?
        MainWindowController.reviewUnsavedChanges(in: [first, clean, second]) { result = $0 }
        #expect(result == false)
        #expect(askedFirst() == ["one.md"])
        #expect(askedSecond() == ["two.md"])
        // The quit is off, so the answer given for it no longer stands:
        // both windows still hold unsaved text and ask again.
        #expect(first.hasUnreviewedChanges)
        #expect(second.hasUnreviewedChanges)

        let askedFirstAgain = script(first, [.discard])
        let askedSecondAgain = script(second, [.discard])
        MainWindowController.reviewUnsavedChanges(in: [first, clean, second]) { result = $0 }
        #expect(result == true)
        #expect(askedFirstAgain() == ["one.md"])
        #expect(askedSecondAgain() == ["two.md"])
    }

    /// "Don't Save" in one window, Cancel in the next: closing the first
    /// window later skipped its prompt and dropped its recovery snapshot.
    @Test("After a cancelled quit, closing a window still asks about its unsaved text")
    func cancelledQuitThenClose() throws {
        let first = makeWindow(), second = makeWindow()
        _ = try openEdited("kept.md", in: first)
        _ = try openEdited("other.md", in: second)
        _ = script(first, [.discard])
        _ = script(second, [.cancel])
        MainWindowController.reviewUnsavedChanges(in: [first, second]) { _ in }

        let asked = script(first, [.cancel])
        #expect(first.windowShouldClose(first.window!) == false)
        #expect(asked() == ["kept.md"])
    }

    /// The file's own encoding cannot hold an emoji; without a way out,
    /// every save and Save As failed and the text could never be saved.
    @Test("Text a legacy encoding cannot hold is saved as UTF-8 once agreed to")
    func saveAsUTF8() throws {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let url = scratch.appendingPathComponent("latin.md")
        try #require("café\n".data(using: .isoLatin1)).write(to: url)
        let controller = makeWindow()
        controller.open(url: url)
        let document = try #require(controller.documents.first { $0.url == url })
        #expect(document.format.encoding != .utf8)
        document.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "😀 ")

        var answers = [false, true]
        controller.askToConvertToUTF8 = { _, answer in answer(answers.removeFirst()) }
        var saved: Bool?
        controller.save(document: document) { saved = $0 }
        #expect(saved == false)
        #expect(document.isDirty)
        #expect(try Data(contentsOf: url) == "café\n".data(using: .isoLatin1))

        controller.save(document: document) { saved = $0 }
        #expect(saved == true)
        #expect(!document.isDirty)
        #expect(document.format.encoding == .utf8)
        #expect(try String(contentsOf: url, encoding: .utf8) == "😀 café\n")
    }

    @Test("Quitting with nothing unsaved asks nothing")
    func quitClean() {
        let controller = makeWindow()
        controller.newDocument()
        let asked = script(controller, [])
        var result: Bool?
        MainWindowController.reviewUnsavedChanges(in: [controller]) { result = $0 }
        #expect(result == true)
        #expect(asked().isEmpty)
    }

    @Test("A torn-off tab keeps its unsaved text and its undo history")
    func tearOff() throws {
        let source = makeWindow()
        source.newDocument()
        let document = try openEdited("moving.md", in: source)
        document.undoManager.groupsByEvent = false
        document.undoManager.beginUndoGrouping()
        let editor = EditorViewController(textStorage: document.storage, undoManager: document.undoManager)
        editor.textView.insertText("more ", replacementRange: NSRange(location: 0, length: 0))
        document.undoManager.endUndoGrouping()
        editor.detachFromStorage()

        var target: MainWindowController?
        source.onMoveToNewWindow = { moved in
            let window = makeWindow()
            window.adopt(moved)
            target = window
        }
        source.select(index: try #require(source.documents.firstIndex { $0 === document }))
        source.moveTabToNewWindow(nil)

        let destination = try #require(target)
        #expect(!source.documents.contains { $0 === document })
        #expect(destination.documents.contains { $0 === document })
        #expect(document.isDirty)
        #expect(document.text == "more edited saved\n")
        #expect(destination.activeDocument === document)
        document.undoManager.undo()
        #expect(document.text == "edited saved\n")
    }

    @Test("A lone tab is not torn off: it already has its window")
    func tearOffLoneTab() throws {
        let controller = makeWindow()
        _ = try openEdited("alone.md", in: controller)
        var moved = false
        controller.onMoveToNewWindow = { _ in moved = true }
        controller.moveTabToNewWindow(nil)
        #expect(!moved)
        #expect(controller.documents.count == 1)
    }

    @Test("Recovery writes only documents changed since their last snapshot")
    func recoveryWritesChanges() throws {
        let controller = makeWindow()
        let document = try openEdited("recover.md", in: controller)
        let snapshot = scratch.appendingPathComponent("Recovery/\(document.id.uuidString).json")
        func recorded() -> String? { controller.recovery.snapshots().first { $0.id == document.id }?.text }

        controller.writeRecoverySnapshots()
        #expect(recorded() == "edited saved\n")

        // Unchanged since: not written again, so a snapshot removed behind its back stays gone.
        try FileManager.default.removeItem(at: snapshot)
        controller.writeRecoverySnapshots()
        #expect(recorded() == nil)
        // Unless every snapshot is being rewritten, after the store was cleared.
        controller.writeRecoverySnapshots(rewriting: true)
        #expect(recorded() == "edited saved\n")

        document.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "more ")
        controller.writeRecoverySnapshots()
        #expect(recorded() == "more edited saved\n")

        // Saved: nothing left to recover.
        controller.save(document: document)
        #expect(recorded() == nil)
        #expect(!FileManager.default.fileExists(atPath: snapshot.path))
    }

    @Test("⌘1…⌘8 pick a tab by position and ⌘9 the last; a tab number past the end does nothing")
    func selectTabByNumber() throws {
        let controller = makeWindow()
        for _ in 0..<4 { controller.newDocument() }
        func press(_ tag: Int) {
            let item = NSMenuItem()
            item.tag = tag
            controller.selectDocumentTab(item)
        }
        press(2)
        #expect(controller.activeDocument === controller.documents[1])
        press(9)
        #expect(controller.activeDocument === controller.documents.last)
        press(1)
        press(6)
        #expect(controller.activeDocument === controller.documents[0])
    }

    @Test("Reopen Closed Tab brings back the most recently closed file")
    func reopenClosedTab() throws {
        let controller = makeWindow()
        let first = try openEdited("first.md", in: controller)
        let second = try openEdited("second.md", in: controller)
        script(controller, [.discard, .discard])()
        let urls = [first.url, second.url]
        controller.closeDocument(at: controller.documents.firstIndex { $0 === first }!)
        controller.closeDocument(at: controller.documents.firstIndex { $0 === second }!)
        #expect(controller.documents.allSatisfy { !urls.contains($0.url) })

        controller.reopenClosedTab(nil)
        #expect(controller.activeDocument?.url == second.url)
        controller.reopenClosedTab(nil)
        #expect(controller.activeDocument?.url == first.url)
    }

    @Test("Restoring a session makes an editor only for the tab it shows, and keeps the rest as saved")
    func restoreIsLazy() throws {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let tabs = try (0..<3).map { index -> Session.Tab in
            let url = scratch.appendingPathComponent("restored\(index).md")
            try String(repeating: "line\n", count: 50).write(to: url, atomically: true, encoding: .utf8)
            return Session.Tab(url: url, selectedLocation: 10 * (index + 1), sourceMode: index == 2, typewriterMode: nil, focusMode: nil)
        }
        let controller = makeWindow()
        controller.restore(Session.Window(tabs: tabs, selectedIndex: 1, workspace: nil, frame: nil))
        #expect(controller.documents.map(\.url) == tabs.map(\.url))
        #expect(controller.activeDocument?.url == tabs[1].url)
        #expect(controller.editorCount == 1)
        // Tabs not shown yet go back into the session as they came.
        let session = controller.windowSession()
        #expect(session.selectedIndex == 1)
        #expect(session.tabs.map(\.selectedLocation) == [10, 20, 30])
        #expect(session.tabs[2].sourceMode == true)

        controller.select(index: 2)
        #expect(controller.editorCount == 2)
        #expect(controller.windowSession().tabs[2].selectedLocation == 30)
        #expect(controller.windowSession().tabs[2].sourceMode == true)
    }
}
