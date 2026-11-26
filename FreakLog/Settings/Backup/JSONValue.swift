import Foundation

// Any JSON value, for the parts of a backup that follow the data model and the settings instead of fixed types
enum JSONValue: Codable, Hashable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(encoding value: some Encodable) throws {
    let data = try JSONEncoder().encode(value)
    self = try JSONDecoder().decode(JSONValue.self, from: data)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let array = try? container.decode([JSONValue].self) {
      self = .array(array)
    } else {
      self = try .object(container.decode([String: JSONValue].self))
    }
  }

  var string: String? {
    if case .string(let string) = self { string } else { nil }
  }

  var number: Double? {
    if case .number(let number) = self { number } else { nil }
  }

  var bool: Bool? {
    if case .bool(let bool) = self { bool } else { nil }
  }

  var object: [String: JSONValue]? {
    if case .object(let object) = self { object } else { nil }
  }

  var array: [JSONValue]? {
    if case .array(let array) = self { array } else { nil }
  }

  subscript(key: String) -> JSONValue? {
    object?[key]
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let bool): try container.encode(bool)
    case .number(let number): try container.encode(number)
    case .string(let string): try container.encode(string)
    case .array(let array): try container.encode(array)
    case .object(let object): try container.encode(object)
    }
  }
}
