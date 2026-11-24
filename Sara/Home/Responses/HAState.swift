import Foundation

struct HAState: Equatable {
    var state: String
    var attributes: [String: HAValue] = [:]
    var entityID: String?

    func attribute(_ key: String) -> Any? { attributes[key]?.any }
}

extension HAState: Decodable {
    private enum Keys: String, CodingKey { case state, attributes, s, a, entity_id }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? container.decode(String.self, forKey: .s)
        attributes = try container.decodeIfPresent([String: HAValue].self, forKey: .attributes)
            ?? container.decodeIfPresent([String: HAValue].self, forKey: .a) ?? [:]
        entityID = try container.decodeIfPresent(String.self, forKey: .entity_id)
    }
}
