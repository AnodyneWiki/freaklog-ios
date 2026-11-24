import SwiftUI

// MARK: - AssistantMarkdownText

// Shows the Markdown models write: headings, lists, quotes, code blocks and paragraphs, with bold, italics,
// code and links inside them. Anything else stays as written.
struct AssistantMarkdownText: View {
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
        view(for: block)
      }
    }
    .textSelection(.enabled)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func view(for block: MarkdownBlock) -> some View {
    switch block {
    case .heading(let level, let text):
      Text(Self.inline(text))
        .font(level <= 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
    case .paragraph(let text):
      Text(Self.inline(text))
    case .listItem(let marker, let text, let depth):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(marker)
          .monospacedDigit()
          .foregroundColor(.secondary)
        Text(Self.inline(text))
      }
      .padding(.leading, Double(depth) * 16)
    case .quote(let text):
      Text(Self.inline(text))
        .foregroundColor(.secondary)
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
          Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
        }
    case .code(let text):
      ScrollView(.horizontal, showsIndicators: false) {
        Text(text)
          .font(.callout.monospaced())
          .padding(10)
      }
      .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    case .rule:
      Divider()
    }
  }

  private static func inline(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
  }
}

// MARK: - MarkdownBlock

enum MarkdownBlock: Equatable {
  case heading(level: Int, text: String)
  case paragraph(String)
  case listItem(marker: String, text: String, depth: Int)
  case quote(String)
  case code(String)
  case rule

  static func parse(_ markdown: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    var code: [String]?

    func endParagraph() {
      if !paragraph.isEmpty {
        blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        paragraph = []
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
          code = []
        }
        continue
      }
      if code != nil {
        code?.append(line)
        continue
      }
      if trimmed.isEmpty {
        endParagraph()
      } else if let heading = heading(in: trimmed) {
        endParagraph()
        blocks.append(heading)
      } else if trimmed.count >= 3, Set(trimmed.filter { $0 != " " }).count == 1, "-*_".contains(trimmed.first!) {
        endParagraph()
        blocks.append(.rule)
      } else if let item = listItem(in: line) {
        endParagraph()
        blocks.append(item)
      } else if trimmed.hasPrefix(">") {
        endParagraph()
        let text = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        if case .quote(let previous) = blocks.last {
          blocks[blocks.count - 1] = .quote(previous + "\n" + text)
        } else {
          blocks.append(.quote(text))
        }
      } else if case .listItem(let marker, let text, let depth) = blocks.last, paragraph.isEmpty, line.first == " " {
        // An indented line continues the list item above it
        blocks[blocks.count - 1] = .listItem(marker: marker, text: text + "\n" + trimmed, depth: depth)
      } else {
        paragraph.append(trimmed)
      }
    }
    if let lines = code {
      blocks.append(.code(lines.joined(separator: "\n")))
    }
    endParagraph()
    return blocks
  }

  private static func heading(in line: String) -> MarkdownBlock? {
    let hashes = line.prefix { $0 == "#" }.count
    guard (1 ... 6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
    return .heading(level: hashes, text: line.dropFirst(hashes).trimmingCharacters(in: .whitespaces))
  }

  private static func listItem(in line: String) -> MarkdownBlock? {
    let indent = line.prefix { $0 == " " || $0 == "\t" }.count
    let rest = line.dropFirst(indent)
    let depth = min(indent / 2, 4)
    if let first = rest.first, "-*+•".contains(first), rest.dropFirst().first == " " {
      return .listItem(marker: "•", text: rest.dropFirst(2).trimmingCharacters(in: .whitespaces), depth: depth)
    }
    let digits = rest.prefix { $0.isNumber }
    guard !digits.isEmpty, digits.count <= 3 else { return nil }
    let afterDigits = rest.dropFirst(digits.count)
    guard let separator = afterDigits.first, separator == "." || separator == ")", afterDigits.dropFirst().first == " " else {
      return nil
    }
    return .listItem(marker: digits + ".", text: afterDigits.dropFirst(2).trimmingCharacters(in: .whitespaces), depth: depth)
  }
}
