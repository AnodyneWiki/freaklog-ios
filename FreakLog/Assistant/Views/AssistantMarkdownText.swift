import SwiftUI

// Shows the Markdown models write: headings, lists, tables, quotes, code blocks and paragraphs, with bold,
// italics, code and links inside them. Anything else stays as written.
struct AssistantMarkdownText: View {
  let text: String

  var body: some View {
    let blocks = MarkdownBlock.parse(text)
    VStack(alignment: .leading, spacing: 12) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
        view(for: block)
          // A heading belongs to what follows it, so it keeps more room above than below
          .padding(.top, index > 0 && block.isHeading ? 6 : 0)
      }
    }
    .lineSpacing(2)
    .textSelection(.enabled)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func view(for block: MarkdownBlock) -> some View {
    switch block {
    case .heading(let level, let text):
      Text(Self.inline(text))
        .font(level <= 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.weight(.semibold))
    case .paragraph(let text):
      Text(Self.inline(text))
    case .list(let items):
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(item.marker ?? Self.bullets[min(item.depth, Self.bullets.count - 1)])
              .monospacedDigit()
              .foregroundColor(.secondary)
              .frame(minWidth: item.marker == nil ? 10 : 18, alignment: .trailing)
            Text(Self.inline(item.text))
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(.leading, Double(item.depth) * 18)
        }
      }
    case .table(let header, let rows):
      table(header: header, rows: rows)
    case .quote(let text):
      Text(Self.inline(text))
        .foregroundColor(.secondary)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
          RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 3)
        }
    case .code(let text):
      ScrollView(.horizontal, showsIndicators: false) {
        Text(text)
          .font(.callout.monospaced())
          .padding(12)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    case .rule:
      Divider()
    }
  }

  private func table(header: [String], rows: [[String]]) -> some View {
    let columns = max(header.count, rows.map(\.count).max() ?? 0)
    return ScrollView(.horizontal, showsIndicators: false) {
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
        if !header.isEmpty {
          GridRow {
            ForEach(0 ..< columns, id: \.self) { column in
              Text(Self.inline(column < header.count ? header[column] : ""))
                .font(.subheadline.weight(.semibold))
            }
          }
          Divider()
        }
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          GridRow {
            ForEach(0 ..< columns, id: \.self) { column in
              Text(Self.inline(column < row.count ? row[column] : ""))
                .font(.subheadline)
            }
          }
        }
      }
      .padding(12)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
  }

  private static let bullets = ["•", "◦", "▪︎"]

  private static func inline(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
  }
}

enum MarkdownBlock: Equatable {
  case heading(level: Int, text: String)
  case paragraph(String)
  case list([ListItem])
  case table(header: [String], rows: [[String]])
  case quote(String)
  case code(String)
  case rule

  struct ListItem: Equatable {
    // The number of an ordered item, e.g. "2.", nil for a bullet
    let marker: String?
    var text: String
    let depth: Int
  }

  var isHeading: Bool {
    if case .heading = self { true } else { false }
  }

  static func parse(_ markdown: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    var code: [String]?
    var tableLines: [String] = []

    func endParagraph() {
      if !paragraph.isEmpty {
        blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        paragraph = []
      }
    }

    func endTable() {
      if !tableLines.isEmpty {
        blocks.append(table(from: tableLines))
        tableLines = []
      }
    }

    for line in markdown.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") {
        if let lines = code {
          blocks.append(.code(lines.joined(separator: "\n")))
          code = nil
        } else {
          endParagraph()
          endTable()
          code = []
        }
        continue
      }
      if code != nil {
        code?.append(line)
        continue
      }
      if trimmed.hasPrefix("|"), trimmed.dropFirst().contains("|") {
        endParagraph()
        tableLines.append(trimmed)
        continue
      }
      endTable()
      if trimmed.isEmpty {
        endParagraph()
      } else if let heading = heading(in: trimmed) {
        endParagraph()
        blocks.append(heading)
      } else if let marker = trimmed.first, "-*_".contains(marker),
                trimmed.filter({ !$0.isWhitespace }).count >= 3, trimmed.allSatisfy({ $0 == marker || $0.isWhitespace }) {
        endParagraph()
        blocks.append(.rule)
      } else if let item = listItem(in: line) {
        endParagraph()
        if case .list(var items) = blocks.last {
          items.append(item)
          blocks[blocks.count - 1] = .list(items)
        } else {
          blocks.append(.list([item]))
        }
      } else if trimmed.hasPrefix(">") {
        endParagraph()
        let text = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        if case .quote(let previous) = blocks.last {
          blocks[blocks.count - 1] = .quote(previous + "\n" + text)
        } else {
          blocks.append(.quote(text))
        }
      } else if case .list(var items) = blocks.last, paragraph.isEmpty, line.first == " " || line.first == "\t" {
        // An indented line continues the list item above it
        items[items.count - 1].text += "\n" + trimmed
        blocks[blocks.count - 1] = .list(items)
      } else {
        paragraph.append(trimmed)
      }
    }
    if let lines = code {
      blocks.append(.code(lines.joined(separator: "\n")))
    }
    endTable()
    endParagraph()
    return blocks
  }

  private static func heading(in line: String) -> MarkdownBlock? {
    let hashes = line.prefix { $0 == "#" }.count
    guard (1 ... 6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
    return .heading(level: hashes, text: line.dropFirst(hashes).trimmingCharacters(in: .whitespaces))
  }

  private static func listItem(in line: String) -> ListItem? {
    let indent = line.prefix { $0 == " " || $0 == "\t" }.count
    let rest = line.dropFirst(indent)
    let depth = min(indent / 2, 4)
    if let first = rest.first, "-*+•".contains(first), rest.dropFirst().first == " " {
      return ListItem(marker: nil, text: rest.dropFirst(2).trimmingCharacters(in: .whitespaces), depth: depth)
    }
    let digits = rest.prefix { $0.isNumber }
    guard !digits.isEmpty, digits.count <= 3 else { return nil }
    let afterDigits = rest.dropFirst(digits.count)
    guard let separator = afterDigits.first, separator == "." || separator == ")", afterDigits.dropFirst().first == " " else {
      return nil
    }
    return ListItem(marker: digits + ".", text: afterDigits.dropFirst(2).trimmingCharacters(in: .whitespaces), depth: depth)
  }

  // A table's first row is its header when a separator row (|---|:--:|) follows it
  private static func table(from lines: [String]) -> MarkdownBlock {
    func cells(_ line: String) -> [String] {
      var content = Substring(line)
      if content.hasPrefix("|") {
        content = content.dropFirst()
      }
      if content.hasSuffix("|") {
        content = content.dropLast()
      }
      return content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    func isSeparator(_ line: String) -> Bool {
      cells(line).allSatisfy { cell in !cell.isEmpty && cell.allSatisfy { "-:".contains($0) } }
    }
    guard lines.count > 1, isSeparator(lines[1]) else {
      return .table(header: [], rows: lines.map(cells))
    }
    return .table(header: cells(lines[0]), rows: lines.dropFirst(2).map(cells))
  }
}
