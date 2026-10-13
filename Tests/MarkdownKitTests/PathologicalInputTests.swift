import Foundation
import Testing
@testable import MarkdownKit

/// Inputs that once took time growing with the square of their length:
/// a paragraph of them froze export and Quick Look for seconds or minutes.
/// Each runs at a size the old code took seconds over in a release build;
/// the budgets are generous for a debug build and still far below that.
@Suite("Pathological input")
struct PathologicalInputTests {
    private static func seconds(_ markdown: String) -> Double {
        let elapsed = ContinuousClock().measure { _ = HTMLRenderer().render(markdown: markdown) }
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    @Test("Unclosed comments, processing instructions and CDATA", arguments: ["a <!-- ", "a <? ", "a <![CDATA[ ", "a <!X "])
    func unclosedRawHTML(_ opener: String) {
        let time = Self.seconds(String(repeating: opener, count: 10_000))
        #expect(time < 1, "\(time) s")
    }

    @Test("Unclosed math")
    func unclosedMath() {
        let time = Self.seconds(String(repeating: "$1 ", count: 20_000))
        #expect(time < 1, "\(time) s")
    }

    @Test("Long runs of emphasis", arguments: ["*a* ", "*a", "_a_ "])
    func emphasis(_ unit: String) {
        let time = Self.seconds(String(repeating: unit, count: 50_000))
        #expect(time < 2, "\(time) s")
    }

    @Test("Nested and unclosed brackets")
    func brackets() {
        let nested = Self.seconds(String(repeating: "[", count: 20_000) + String(repeating: "]", count: 20_000))
        let links = Self.seconds(String(repeating: "[", count: 20_000) + String(repeating: "[a](b) ", count: 20_000))
        #expect(nested < 1, "\(nested) s")
        #expect(links < 2, "\(links) s")
    }

    /// Each trailing `)` of a bare URL recounted the parentheses before it.
    @Test("Bare URL followed by a run of closing parentheses")
    func bareURLParentheses() {
        let time = Self.seconds("https://x.com/" + String(repeating: ")", count: 40_000))
        #expect(time < 1, "\(time) s")
        #expect(HTMLRenderer().render(markdown: "https://x.com/(a))") == "<p><a href=\"https://x.com/(a)\">https://x.com/(a)</a>)</p>\n")
    }

    /// Nesting past any real document's once overflowed the stack: the
    /// tree is built, torn down and rendered recursively.
    @Test("Deeply nested emphasis, quotes and lists")
    func deepNesting() {
        let emphasis = Self.seconds(String(repeating: "**a ", count: 50_000) + String(repeating: " a**", count: 50_000))
        let quotes = Self.seconds(String(repeating: ">", count: 50_000) + " a")
        let lists = Self.seconds(String(repeating: "- ", count: 50_000) + "a")
        #expect(emphasis < 2, "\(emphasis) s")
        #expect(quotes < 1, "\(quotes) s")
        #expect(lists < 1, "\(lists) s")
        _ = InlineParser.parse(Array((String(repeating: "*a ", count: 50_000) + String(repeating: " a*", count: 50_000)).utf16))
    }

    /// Each open list rescanned the line's indentation.
    @Test("Lines indented under many nested lists")
    func indentedNestedLists() {
        let time = Self.seconds((0..<1_500).map { String(repeating: "  ", count: $0) + "- a" }.joined(separator: "\n"))
        #expect(time < 2, "\(time) s")
    }

    /// A wide header over many one-cell rows filled every row in.
    @Test("Table rows padded to a wide header")
    func tablePadding() {
        let markdown = "|" + String(repeating: " a |", count: 3_000) + "\n|" + String(repeating: " - |", count: 3_000) + "\n" + String(repeating: "a\n", count: 3_000)
        var html = ""
        let elapsed = ContinuousClock().measure { html = HTMLRenderer().render(markdown: markdown) }
        #expect(html.utf8.count < 2_000_000, "\(html.utf8.count) bytes")
        #expect(elapsed < .seconds(2), "\(elapsed)")
    }

    @Test("Many setext headings, definitions and footnotes")
    func manyBlocks() {
        let setext = Self.seconds(String(repeating: "a\n=\n", count: 40_000))
        let definitions = Self.seconds((0..<40_000).map { "[l\($0)]: /u" }.joined(separator: "\n"))
        let footnotes = Self.seconds(
            (0..<20_000).map { "a[^\($0)]" }.joined(separator: " ") + "\n\n" + (0..<20_000).map { "[^\($0)]: x" }.joined(separator: "\n")
        )
        // About 1 s each on a Mac, 4–5 on a CI runner: the limit is there to catch
        // quadratic slowdowns, not to time the machine.
        #expect(setext < 10, "\(setext) s")
        #expect(definitions < 10, "\(definitions) s")
        #expect(footnotes < 10, "\(footnotes) s")
    }

    /// A floor on where openers are searched for was kept as an index into
    /// pieces that each match then spliced, so it drifted past real openers.
    @Test("Emphasis after an earlier match still finds its opener")
    func openerFloorSurvivesMatches() {
        #expect(HTMLRenderer().render(markdown: "_a*_*a*") == "<p><em>a*</em><em>a</em></p>\n")
        #expect(HTMLRenderer().render(markdown: "*a_*_*_") == "<p><em>a_</em><em>*</em></p>\n")
    }
}
