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

    @Test("Revealing a heading or quote leaves the lines below in place; a quote's marker hangs")
    func revealHangsMarkers() {
        let storage = MarkdownTextStorage(theme: .light)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Intro.\n\n## Try it here\n\n> Quoted\n\nAfter.\n")
        let (manager, container) = layoutManager(contiguous: true, for: storage)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
        textView.textContainerInset = NSSize(width: 100, height: 0)

        /// Where the first glyph of some text sits, and where the last line starts.
        func positions(of text: String) -> (x: CGFloat, after: CGFloat) {
            manager.ensureLayout(for: container)
            let index = (storage.string as NSString).range(of: text).location
            let glyph = manager.glyphIndexForCharacter(at: index)
            let fragment = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let last = manager.lineFragmentRect(forGlyphAt: manager.numberOfGlyphs - 1, effectiveRange: nil)
            return (fragment.minX + manager.location(forGlyphAt: glyph).x, last.minY)
        }

        let heading = positions(of: "Try it here")
        let quote = positions(of: "Quoted")
        storage.revealedLines = 2...2
        let revealedHeading = positions(of: "Try it here")
        // A heading's `## ` makes room (the text glides over), but the
        // heading keeps its height, so nothing below it moves.
        #expect(revealedHeading.x > heading.x + 1)
        #expect(abs(revealedHeading.after - heading.after) < 0.5)
        storage.revealedLines = 4...4
        let revealedQuote = positions(of: "Quoted")
        #expect(abs(revealedQuote.x - quote.x) < 0.5)
        #expect(abs(revealedQuote.after - quote.after) < 0.5)
    }

    @Test("A reveal glides: its first frame draws every word where it was, its markers unseen")
    func revealMotionStartsFromOldLayout() {
        let storage = MarkdownTextStorage(theme: .light)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Intro.\n\nSome **bold** words here.\n")
        let (manager, container) = layoutManager(contiguous: true, for: storage)
        manager.ensureLayout(for: container)
        let text = storage.string as NSString
        func x(of word: String) -> CGFloat {
            let glyph = manager.glyphIndexForCharacter(at: text.range(of: word).location)
            return manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minX + manager.location(forGlyphAt: glyph).x
        }
        let before = x(of: "words")

        let moved = manager.animateReveal(across: [storage.characterRange(forLines: 2...2)]) { storage.revealedLines = 2...2 }
        #expect(moved)
        let motion = try! #require(manager.revealMotion)
        let wordsGlyph = manager.glyphIndexForCharacter(at: text.range(of: "words").location)
        // At the start, layout plus the motion's offset is the old place.
        #expect(abs(x(of: "words") + motion.offset(forGlyph: wordsGlyph, progress: 0).dx - before) < 0.5)
        #expect(motion.offset(forGlyph: wordsGlyph, progress: 1) == .zero)
        // The markers that appeared fade in rather than slide.
        let marker = manager.glyphIndexForCharacter(at: text.range(of: "**").location)
        #expect(motion.segment(containing: marker)?.fadesIn == true)
        #expect(motion.progress(at: motion.start) == 0)
        #expect(motion.progress(at: motion.start + motion.duration) == 1)
    }
}
