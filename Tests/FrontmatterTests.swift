import XCTest
@testable import DotBrain

final class FrontmatterTests: XCTestCase {

    private func roundtrip(_ fm: Frontmatter) -> Frontmatter {
        Frontmatter.parse(markdown: fm.stringify() + "\nbody").frontmatter
    }

    func testQuotedSummaryRoundtripIsIdentity() {
        var fm = Frontmatter(tags: ["swift"])
        fm.summary = #"He said "hi" and left"#

        XCTAssertEqual(roundtrip(fm).summary, fm.summary)
    }

    func testSummaryEndingInApostropheSurvives() {
        var fm = Frontmatter(tags: [])
        fm.summary = "rock 'n roll'"

        XCTAssertEqual(roundtrip(fm).summary, fm.summary)
    }

    func testLiteralBackslashNIsNotConvertedToNewline() {
        var fm = Frontmatter(tags: [])
        fm.summary = #"path is C:\new\table"#

        XCTAssertEqual(roundtrip(fm).summary, fm.summary)
    }

    func testRepeatedRewritesDoNotAccumulateEscapes() {
        var fm = Frontmatter(tags: [])
        fm.summary = #"quote " inside"#

        var current = fm
        for _ in 0..<3 { current = roundtrip(current) }
        XCTAssertEqual(current.summary, fm.summary)
    }

    func testUnknownKeysArePreservedThroughRewrite() {
        let markdown = """
        ---
        para: resource
        tags: ["swift"]
        aliases:
          - my-alias
          - other-alias
        cssclasses: wide
        ---
        body text
        """

        let (fm, body) = Frontmatter.parse(markdown: markdown)
        let rewritten = fm.stringify() + "\n" + body

        XCTAssertTrue(rewritten.contains("aliases:"), "unknown list key must survive")
        XCTAssertTrue(rewritten.contains("- my-alias"), "unknown list items must survive")
        XCTAssertTrue(rewritten.contains("cssclasses: wide"), "unknown scalar key must survive")
        XCTAssertEqual(Frontmatter.parse(markdown: rewritten).frontmatter.tags, ["swift"])
    }

    func testInjectPreservesUnknownKeys() {
        let markdown = """
        ---
        para: resource
        publish: true
        ---
        body
        """

        let injected = Frontmatter.createDefault(tags: ["ai"]).inject(into: markdown)

        XCTAssertTrue(injected.contains("publish: true"))
    }

    func testBlockScalarSummaryContentIsCaptured() {
        let markdown = """
        ---
        summary: >-
          first line
          second line
        tags: []
        ---
        body
        """

        let (fm, _) = Frontmatter.parse(markdown: markdown)
        XCTAssertEqual(fm.summary, "first line\nsecond line")
    }

    func testNewlineInTagCannotInjectFrontmatterKeys() {
        var fm = Frontmatter(tags: ["safe\npara: archive"])
        fm.para = .resource

        let parsed = roundtrip(fm)
        XCTAssertEqual(parsed.para, .resource, "injected key must not override para")
        XCTAssertEqual(parsed.tags, fm.tags, "tag content must roundtrip intact")
    }

    func testLeadingYAMLIndicatorIsQuoted() {
        var fm = Frontmatter(tags: [])
        fm.summary = "*중요* 요약"

        let yaml = fm.stringify()
        XCTAssertTrue(yaml.contains(#"summary: "\#("*중요* 요약")""#),
                      "leading indicator values must be quoted for strict parsers")
        XCTAssertEqual(roundtrip(fm).summary, fm.summary)
    }
}
