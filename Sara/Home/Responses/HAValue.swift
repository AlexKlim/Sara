import Foundation

enum HAValue: Decodable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([HAValue])
    case object([String: HAValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([HAValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: HAValue].self)) }
    }

    var string: String? { if case .string(let value) = self { value } else { nil } }
    var double: Double? { if case .number(let value) = self { value } else { nil } }
    var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
    var object: [String: HAValue]? { if case .object(let value) = self { value } else { nil } }

    subscript(key: String) -> HAValue? { object?[key] }

    var any: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .number(let value): NSNumber(value: value)
        case .string(let value): value
        case .array(let values): values.map(\.any)
        case .object(let values): values.mapValues(\.any)
        }
    }
}
