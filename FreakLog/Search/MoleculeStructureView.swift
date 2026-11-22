import SwiftUI

// A 2D structure drawing from AnodyneWiki, which generates them with the Chemistry Development Kit as SVG:
// bonds are stroked paths or lines (depending on the CDK version), atom labels and wedges filled paths,
// on a white background. They are redrawn natively,
// with black bonds and labels in the text color so they read in dark mode too.
struct MoleculeStructureView: View {
  let drawing: MoleculeDrawing
  let substanceName: String

  init?(svg: String, substanceName: String) {
    guard let drawing = MoleculeDrawing.parse(svg) else { return nil }
    self.drawing = drawing
    self.substanceName = substanceName
  }

  var body: some View {
    Canvas { context, size in
      let viewBox = drawing.viewBox
      let scale = min(size.width / viewBox.width, size.height / viewBox.height)
      let offset = CGPoint(
        x: (size.width - viewBox.width * scale) / 2 - viewBox.minX * scale,
        y: (size.height - viewBox.height * scale) / 2 - viewBox.minY * scale
      )
      context.translateBy(x: offset.x, y: offset.y)
      context.scaleBy(x: scale, y: scale)
      for shape in drawing.shapes {
        if let fill = shape.fill {
          context.fill(shape.path, with: .color(fill.color))
        }
        if let stroke = shape.stroke {
          context.stroke(
            shape.path,
            with: .color(stroke.color),
            style: StrokeStyle(lineWidth: shape.lineWidth, lineCap: .round, lineJoin: .round)
          )
        }
      }
    }
    .aspectRatio(drawing.viewBox.width / drawing.viewBox.height, contentMode: .fit)
    .frame(maxWidth: .infinity, maxHeight: 180)
    .padding(.vertical, 8)
    .accessibilityElement()
    .accessibilityLabel("Structure of \(substanceName)")
    .accessibilityAddTraits(.isImage)
  }
}

struct MoleculeDrawing {
  enum Paint: Equatable {
    // Black in the SVG, drawn in the text color
    case foreground
    case rgb(Double, Double, Double)

    var color: Color {
      switch self {
      case .foreground: .primary
      case let .rgb(red, green, blue): Color(red: red, green: green, blue: blue)
      }
    }
  }

  struct Shape {
    let path: Path
    let fill: Paint?
    let stroke: Paint?
    let lineWidth: CGFloat
  }

  let viewBox: CGRect
  let shapes: [Shape]

  private static var cache: [String: MoleculeDrawing] = [:]

  @MainActor
  static func parse(_ svg: String) -> MoleculeDrawing? {
    if let cached = cache[svg] {
      return cached
    }
    guard let data = svg.data(using: .utf8) else { return nil }
    let delegate = SVGParserDelegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    guard parser.parse(), let viewBox = delegate.viewBox, !delegate.shapes.isEmpty else { return nil }
    let drawing = MoleculeDrawing(viewBox: viewBox, shapes: delegate.shapes)
    cache[svg] = drawing
    return drawing
  }

  // nil for "none" and white, which is the background
  static func paint(_ value: String?) -> Paint?? {
    guard let value else { return .none }
    let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
    if value == "none" || hex == "fff" || hex == "ffffff" {
      return .some(nil)
    }
    let digits = hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : hex
    guard digits.count == 6, let number = UInt64(digits, radix: 16) else { return .some(nil) }
    if number == 0 {
      return .some(.foreground)
    }
    return .some(.rgb(
      Double((number >> 16) & 0xFF) / 255,
      Double((number >> 8) & 0xFF) / 255,
      Double(number & 0xFF) / 255
    ))
  }
}

// Reads the SVG's shapes with their inherited fill, stroke and stroke width
private final class SVGParserDelegate: NSObject, XMLParserDelegate {
  private struct Style {
    var fill: MoleculeDrawing.Paint? = .foreground
    var stroke: MoleculeDrawing.Paint?
    var lineWidth: CGFloat = 1
  }

  var viewBox: CGRect?
  var shapes: [MoleculeDrawing.Shape] = []
  private var styles = [Style()]

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName: String?,
    attributes: [String: String] = [:]
  ) {
    var style = styles.last ?? Style()
    if let fill = MoleculeDrawing.paint(attributes["fill"]) {
      style.fill = fill
    }
    if let stroke = MoleculeDrawing.paint(attributes["stroke"]) {
      style.stroke = stroke
    }
    if let width = attributes["stroke-width"].flatMap(Double.init) {
      style.lineWidth = width
    }
    styles.append(style)
    switch elementName {
    case "svg":
      let numbers = (attributes["viewBox"] ?? "").split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
      if numbers.count == 4, numbers[2] > 0, numbers[3] > 0 {
        viewBox = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
      }
    default:
      if let path = Self.path(of: elementName, attributes), style.fill != nil || style.stroke != nil {
        shapes.append(.init(path: path, fill: style.fill, stroke: style.stroke, lineWidth: style.lineWidth))
      }
    }
  }

  private static func path(of element: String, _ attributes: [String: String]) -> Path? {
    func number(_ name: String) -> CGFloat? {
      attributes[name].flatMap { Double($0) }.map { CGFloat($0) }
    }
    switch element {
    case "path":
      return attributes["d"].flatMap(SVGPath.parse)
    case "line":
      guard let x1 = number("x1"), let y1 = number("y1"), let x2 = number("x2"), let y2 = number("y2") else { return nil }
      var path = Path()
      path.move(to: CGPoint(x: x1, y: y1))
      path.addLine(to: CGPoint(x: x2, y: y2))
      return path
    case "rect":
      guard let width = number("width"), let height = number("height") else { return nil }
      return Path(CGRect(x: number("x") ?? 0, y: number("y") ?? 0, width: width, height: height))
    case "polyline", "polygon":
      let values = (attributes["points"] ?? "").split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
      let points = stride(from: 0, to: values.count - 1, by: 2).map { CGPoint(x: values[$0], y: values[$0 + 1]) }
      guard points.count >= 2 else { return nil }
      var path = Path()
      path.addLines(points)
      if element == "polygon" {
        path.closeSubpath()
      }
      return path
    case "circle", "ellipse":
      guard let centerX = number("cx"), let centerY = number("cy"),
            let radiusX = number("rx") ?? number("r"), let radiusY = number("ry") ?? number("r")
      else { return nil }
      return Path(ellipseIn: CGRect(x: centerX - radiusX, y: centerY - radiusY, width: 2 * radiusX, height: 2 * radiusY))
    default:
      return nil
    }
  }

  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
    styles.removeLast()
  }
}

// SVG path data: moves, lines, cubic and quadratic curves with their shorthands, absolute or relative.
// Numbers run together as SVGs allow, e.g. "1.106 10.672.005 15.248" or "13.199-7.62".
enum SVGPath {
  static func parse(_ data: String) -> Path? {
    guard let regex = try? NSRegularExpression(
      pattern: "[MmLlHhVvCcSsQqTtZz]|-?(?:\\d+\\.\\d*|\\.\\d+|\\d+)(?:[eE][-+]?\\d+)?"
    ) else { return nil }
    let tokens = regex.matches(in: data, range: NSRange(data.startIndex..., in: data)).compactMap {
      Range($0.range, in: data).map { String(data[$0]) }
    }
    var path = Path()
    var index = 0
    var command: Character = "M"
    var current = CGPoint.zero
    var start = CGPoint.zero
    var lastControl: CGPoint?
    var lastCommand: Character = "M"

    func number() -> CGFloat? {
      guard index < tokens.count, let value = Double(tokens[index]) else { return nil }
      index += 1
      return value
    }

    func point(relative: Bool) -> CGPoint? {
      guard let x = number(), let y = number() else { return nil }
      return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }

    while index < tokens.count {
      if let letter = tokens[index].first, tokens[index].count == 1, letter.isLetter {
        command = letter
        index += 1
        if command == "Z" || command == "z" {
          path.closeSubpath()
          current = start
          lastCommand = command
          continue
        }
      }
      let relative = command.isLowercase
      switch command.uppercased() {
      case "M":
        guard let target = point(relative: relative) else { return nil }
        path.move(to: target)
        current = target
        start = target
        // Further pairs after a move are lines
        command = relative ? "l" : "L"
      case "L":
        guard let target = point(relative: relative) else { return nil }
        path.addLine(to: target)
        current = target
      case "H":
        guard let x = number() else { return nil }
        current = CGPoint(x: relative ? current.x + x : x, y: current.y)
        path.addLine(to: current)
      case "V":
        guard let y = number() else { return nil }
        current = CGPoint(x: current.x, y: relative ? current.y + y : y)
        path.addLine(to: current)
      case "C":
        guard let control1 = point(relative: relative), let control2 = point(relative: relative),
              let target = point(relative: relative)
        else { return nil }
        path.addCurve(to: target, control1: control1, control2: control2)
        lastControl = control2
        current = target
      case "S":
        let control1 = reflected(lastControl, if: "CcSs".contains(lastCommand), around: current)
        guard let control2 = point(relative: relative), let target = point(relative: relative) else { return nil }
        path.addCurve(to: target, control1: control1, control2: control2)
        lastControl = control2
        current = target
      case "Q":
        guard let control = point(relative: relative), let target = point(relative: relative) else { return nil }
        path.addQuadCurve(to: target, control: control)
        lastControl = control
        current = target
      case "T":
        let control = reflected(lastControl, if: "QqTt".contains(lastCommand), around: current)
        guard let target = point(relative: relative) else { return nil }
        path.addQuadCurve(to: target, control: control)
        lastControl = control
        current = target
      default:
        // Arcs and anything else aren't drawn by the structure generator
        return nil
      }
      lastCommand = command
    }
    return path
  }

  private static func reflected(_ control: CGPoint?, if isSmooth: Bool, around point: CGPoint) -> CGPoint {
    guard isSmooth, let control else { return point }
    return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
  }
}
