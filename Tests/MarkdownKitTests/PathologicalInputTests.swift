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

    /// A floor on where openers are searched for was kept as an index into
    /// pieces that each match then spliced, so it drifted past real openers.
    @Test("Emphasis after an earlier match still finds its opener")
    func openerFloorSurvivesMatches() {
        #expect(HTMLRenderer().render(markdown: "_a*_*a*") == "<p><em>a*</em><em>a</em></p>\n")
        #expect(HTMLRenderer().render(markdown: "*a_*_*_") == "<p><em>a_</em><em>*</em></p>\n")
    }
}
