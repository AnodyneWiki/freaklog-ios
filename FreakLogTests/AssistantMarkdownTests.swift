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
      .listItem(marker: "•", text: "First\nmore", depth: 0),
      .listItem(marker: "2.", text: "Second", depth: 0),
      .quote("Careful"),
      .code("code"),
      .rule,
    ])
  }
}
