import XCTest
@testable import FreakLog

final class AssistantMarkdownTests: XCTestCase {
  func testMarkdownBlocks() {
    let blocks = MarkdownBlock.parse("""
      ## Summary
      You took **MDMA**.
      Then rested.

      - First
        more
        - Nested
      2. Second
      > Careful
      ```
      code
      ```
      ---
      """)
    XCTAssertEqual(blocks, [
      .heading(level: 2, text: "Summary"),
      .paragraph("You took **MDMA**.\nThen rested."),
      .list([
        .init(marker: nil, text: "First\nmore", depth: 0),
        .init(marker: nil, text: "Nested", depth: 1),
        .init(marker: "2.", text: "Second", depth: 0),
      ]),
      .quote("Careful"),
      .code("code"),
      .rule,
    ])
  }

  func testTablesKeepTheirHeader() {
    let blocks = MarkdownBlock.parse("""
      | Substance | Dose |
      |:---|---:|
      | MDMA | 100 mg |
      | Ketamine | 20 mg |
      After.
      """)
    XCTAssertEqual(blocks, [
      .table(header: ["Substance", "Dose"], rows: [["MDMA", "100 mg"], ["Ketamine", "20 mg"]]),
      .paragraph("After."),
    ])
  }
}
