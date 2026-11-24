import Foundation

struct HAStatesEvent {
    var added: [String: HAState] = [:]
    var changed: [String: HAStateChange] = [:]
    var removed: [String] = []
}

extension HAStatesEvent: Decodable {
    private enum Keys: String, CodingKey { case a, c, r }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        added = try container.decodeIfPresent([String: HAState].self, forKey: .a) ?? [:]
        changed = try container.decodeIfPresent([String: HAStateChange].self, forKey: .c) ?? [:]
        removed = try container.decodeIfPresent([String].self, forKey: .r) ?? []
    }
}
