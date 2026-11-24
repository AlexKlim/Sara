import Foundation

struct HAStateChange {
    var state: String?
    var attributes: [String: HAValue] = [:]
    var removedAttributes: [String] = []
}

extension HAStateChange: Decodable {
    private enum Keys: String, CodingKey { case added = "+", removed = "-" }
    private enum Parts: String, CodingKey { case s, a }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        if container.contains(.added) {
            let added = try container.nestedContainer(keyedBy: Parts.self, forKey: .added)
            state = try added.decodeIfPresent(String.self, forKey: .s)
            attributes = try added.decodeIfPresent([String: HAValue].self, forKey: .a) ?? [:]
        }
        if container.contains(.removed) {
            removedAttributes = try container.nestedContainer(keyedBy: Parts.self, forKey: .removed)
                .decodeIfPresent([String].self, forKey: .a) ?? []
        }
    }
}
