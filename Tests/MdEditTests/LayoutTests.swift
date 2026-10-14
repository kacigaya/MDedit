import AppKit
import Testing
@testable import MdEdit

/// Layout kept up to date edit by edit must match laying the document out
/// afresh. Restyling reaches past the edited line (fences, folds, reveals),
/// and each line it restyles has to be invalidated for layout, or the
/// editor shows stale line heights.
///
/// Non-contiguous layout is not an option as things stand: with markers
/// hidden as zero-width glyphs, a heading laid out from its own line comes
/// out taller than one reached from above, so lines would jump as layout
/// filled in.
@MainActor
@Suite("Layout")
struct LayoutTests {
    /// A deterministic generator, so a failure replays.
    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state ^ (state >> 33)
        }
    }

    private func layoutManager(contiguous: Bool, for storage: MarkdownTextStorage) -> (MarkdownLayoutManager, NSTextContainer) {
        let manager = MarkdownLayoutManager()
        manager.allowsNonContiguousLayout = !contiguous
        let container = NSTextContainer(size: CGSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        return (manager, container)
    }

    /// Every line fragment, in order.
    private func fragments(_ manager: NSLayoutManager, _ container: NSTextContainer) -> [CGRect] {
        manager.ensureLayout(for: container)
        var rects: [CGRect] = []
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { rect, _, _, _, _ in
            rects.append(rect)
        }
        return rects
    }

    @Test("Layout kept up through edits matches laying it all out", arguments: [1, 2])
    func onDemandMatchesFull(seed: UInt64) throws {
        var random = Generator(state: seed)
        let storage = MarkdownTextStorage(theme: .light)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: PerformanceTests.document(lines: 600))
        let (lazy, lazyContainer) = layoutManager(contiguous: true, for: storage)
        lazy.ensureLayout(forCharacterRange: NSRange(location: storage.length / 2, length: 3_000))

        let snippets = ["x", "\n", "```\n", "$$\n", "# Heading\n", "**", "| a | b |\n", "> ", "- ", "\n\n", "Term\n: definition\n", "![i](missing.png)\n"]
        for step in 0..<300 {
            let length = storage.length
            switch Int.random(in: 0..<10, using: &random) {
            case 0...4:
                let snippet = snippets.randomElement(using: &random)!
                storage.replaceCharacters(in: NSRange(location: Int.random(in: 0...length, using: &random), length: 0), with: snippet)
            case 5, 6:
                let location = Int.random(in: 0..<max(1, length), using: &random)
                storage.replaceCharacters(in: NSRange(location: location, length: min(Int.random(in: 0...40, using: &random), length - location)), with: "")
            case 7:
                let line = Int.random(in: 0..<storage.structure.lineCount, using: &random)
                storage.revealedLines = line...min(storage.structure.lineCount - 1, line + Int.random(in: 0...5, using: &random))
            case 8:
                let line = Int.random(in: 0..<storage.structure.lineCount, using: &random)
                if storage.foldableRange(forHeadingLine: line) != nil {
                    storage.setFolded(!storage.foldedHeadings.contains(line), headingLine: line)
                } else {
                    storage.unfoldAll()
                }
            default:
                // Something on screen somewhere asks for layout.
                let location = Int.random(in: 0..<max(1, storage.length), using: &random)
                lazy.ensureLayout(forCharacterRange: NSRange(location: location, length: min(2_000, storage.length - location)))
            }
            if step % 100 == 99 {
                let (full, fullContainer) = layoutManager(contiguous: true, for: storage)
                let expected = fragments(full, fullContainer)
                let actual = fragments(lazy, lazyContainer)
                storage.removeLayoutManager(full)
                #expect(actual.count == expected.count, "step \(step)")
                // Laid out in a different order, positions sum up differently in the last bits.
                func same(_ a: CGRect, _ b: CGRect) -> Bool {
                    abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01 && abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
                }
                let first = zip(actual, expected).enumerated().first { !same($0.element.0, $0.element.1) }
                #expect(first == nil, "step \(step): fragment \(first?.offset ?? -1) is \(String(describing: first?.element.0)), not \(String(describing: first?.element.1))")
            }
        }
    }

    /// The caret on an empty document is sized from the typing attributes
    /// alone; without the paragraph style those carry, it came out shorter
    /// than the caret on the first typed line.
    @Test("The caret is the same height before and after the first character")
    func caretHeightOnEmptyDocument() throws {
        let document = Document(theme: .light)
        let editor = EditorViewController(textStorage: document.storage, undoManager: document.undoManager)
        editor.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let textView = editor.textView
        let manager = try #require(textView.layoutManager)
        let container = try #require(textView.textContainer)

        manager.ensureLayout(for: container)
        let empty = manager.extraLineFragmentRect.height

        textView.insertText("e", replacementRange: NSRange(location: 0, length: 0))
        manager.ensureLayout(for: container)
        let typed = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height

        #expect(abs(empty - typed) < 0.01, "empty \(empty), typed \(typed)")
    }
}
