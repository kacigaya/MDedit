import AppKit
import Testing
@testable import MarkdownKit
@testable import MdEdit

@MainActor
@Suite("MarkdownTextStorage")
struct MarkdownTextStorageTests {
    private func storage(_ text: String) -> MarkdownTextStorage {
        let storage = MarkdownTextStorage(theme: .light)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        return storage
    }

    /// The crash this test exists for: type a line, press Return, press
    /// Backspace. The caret's revealed line is then one past the end of a
    /// document that just shrank, and forming that range traps.
    @Test("A revealed line left past the end of a shrunken document is clamped")
    func revealedLineSurvivesShrinking() {
        let storage = storage("hello\n")
        #expect(storage.structure.lineCount == 2)

        storage.revealedLines = 1...1
        // Delete the newline: the document is now one line, and 1...1 is stale.
        storage.replaceCharacters(in: NSRange(location: 5, length: 1), with: "")
        #expect(storage.structure.lineCount == 1)

        storage.revealedLines = 0...0
        #expect(storage.revealedLines == 0...0)
    }

    @Test("Clamping orders its bounds before forming a range")
    func clamping() {
        let storage = storage("one\ntwo\nthree")
        #expect(storage.clampedLineRange(0...0) == 0...0)
        #expect(storage.clampedLineRange(1...2) == 1...2)
        // Entirely past the end collapses onto the last line. This is the case
        // that used to trap: the old code clamped only the upper bound, forming
        // `9...2`.
        #expect(storage.clampedLineRange(9...9) == 2...2)
        #expect(storage.clampedLineRange(1...9) == 1...2)
        #expect(storage.clampedLineRange(-3...1) == 0...1)
    }

    @Test("Deleting the whole document leaves styling intact")
    func deleteEverything() {
        let storage = storage("# title\n\n- a\n- b\n")
        storage.revealedLines = 3...3
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "")
        storage.revealedLines = 0...0
        #expect(storage.length == 0)
        #expect(storage.structure.lineCount == 1)
    }

    @Test("Opening a fence restyles the lines below it")
    func fenceRestyle() {
        let storage = storage("text\nmore\n")
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "```bash\n")
        #expect(storage.structure.info(forLine: 1)?.kind == .codeLine)
    }

    /// Typing a fence's language one character at a time, which is how the bug
    /// was reported.
    @Test("Typing ```bash character by character")
    func typingAFence() {
        let storage = storage("")
        for character in "```bash" {
            storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: String(character))
            storage.revealedLines = 0...0
        }
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: "\n")
        storage.revealedLines = 1...1
        storage.replaceCharacters(in: NSRange(location: storage.length - 1, length: 1), with: "")
        storage.revealedLines = 0...0
        #expect(storage.string == "```bash")
    }

    @Test("Restyling for a new theme matches styling from scratch")
    func restyleMatchesFreshStyling() {
        let text = PerformanceTests.document(lines: 500)
        let restyled = MarkdownTextStorage(theme: .dark)
        restyled.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        restyled.theme = .light
        let fresh = storage(text)
        let whole = NSRange(location: 0, length: fresh.length)
        #expect(restyled.attributedSubstring(from: whole).isEqual(to: fresh.attributedSubstring(from: whole)))
    }

    @Test("Handing the editor the theme it already has does not restyle")
    func sameThemeIsFree() {
        let storage = storage("# Title\n\nSome **bold** text.\n")
        var edits = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil
        ) { _ in edits += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        storage.theme = .light
        #expect(edits == 0)
        storage.theme = .dark
        #expect(edits == 1)
    }

    @Test("Moving a revealed range restyles to the same result as starting there")
    func revealChangesMatchFreshStyling() {
        let text = PerformanceTests.document(lines: 300) + "Term\n: definition\n\n$$\nx^2\n$$\n"
        let moved = storage(text)
        let last = moved.structure.lineCount - 1
        // Grow, shrink, jump, overlap and clear, as selections do.
        let steps: [ClosedRange<Int>?] = [5...5, 5...9, 5...40, 30...60, 2...3, 200...last, last...last, 150...250, nil, 0...last, 7...7]
        for step in steps {
            moved.revealedLines = step
            let fresh = storage(text)
            fresh.revealedLines = step
            let whole = NSRange(location: 0, length: fresh.length)
            #expect(moved.attributedSubstring(from: whole).isEqual(to: fresh.attributedSubstring(from: whole)), "after \(String(describing: step))")
        }
    }

    @Test("Every entry of a long definition list is styled as one, and long prose is not")
    func longDefinitionList() throws {
        let entries = (0..<200).map { "Term \($0)\n: Its definition." }.joined(separator: "\n")
        let prose = (0..<200).map { "Line \($0) of prose, wrapped by hand." }.joined(separator: "\n")
        let storage = storage(entries + "\n\n" + prose + "\n")
        let text = storage.string as NSString
        for term in ["Term 0", "Term 199"] {
            let font = try #require(storage.attribute(.font, at: text.range(of: term).location, effectiveRange: nil) as? NSFont)
            #expect(font.fontDescriptor.symbolicTraits.contains(.bold), "\(term)")
        }
        let lastMarker = text.range(of: ": Its", options: .backwards).location
        #expect(storage.attribute(.mdConcealed, at: lastMarker, effectiveRange: nil) != nil)
        let line = try #require(storage.attribute(.font, at: text.range(of: "Line 150").location, effectiveRange: nil) as? NSFont)
        #expect(!line.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("Putting a document in an editor keeps its styling")
    func editorKeepsStyling() throws {
        let document = Document(text: "Intro.\n\nSome **bold** and `code`.\n", theme: .light)
        let storage = document.storage
        let whole = NSRange(location: 0, length: storage.length)
        let styled = storage.attributedSubstring(from: whole)
        let editor = EditorViewController(textStorage: storage, undoManager: document.undoManager)
        _ = editor.view
        // The caret sits on the first line, which shows as written; the rest is as styled.
        let rest = NSRange(location: 7, length: storage.length - 7)
        #expect(storage.attributedSubstring(from: rest).isEqual(to: styled.attributedSubstring(from: rest)))
        let bold = try #require(storage.attribute(.font, at: (storage.string as NSString).range(of: "bold").location, effectiveRange: nil) as? NSFont)
        #expect(bold.fontDescriptor.symbolicTraits.contains(.bold))
        let code = try #require(storage.attribute(.font, at: (storage.string as NSString).range(of: "code").location, effectiveRange: nil) as? NSFont)
        #expect(code.isFixedPitch)
        _ = whole
    }

    @Test("Markers styled from the cache match styling from scratch through mode and theme changes")
    func markerCacheFollowsModeAndTheme() {
        let text = PerformanceTests.document(lines: 200)
        let changed = storage(text)
        changed.revealedLines = 3...8
        changed.sourceMode = true
        changed.theme = .dark
        changed.sourceMode = false
        let fresh = MarkdownTextStorage(theme: .dark)
        fresh.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        fresh.revealedLines = 3...8
        let whole = NSRange(location: 0, length: fresh.length)
        #expect(changed.attributedSubstring(from: whole).isEqual(to: fresh.attributedSubstring(from: whole)))
    }
}
