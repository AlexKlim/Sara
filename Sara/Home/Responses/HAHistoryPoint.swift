import Foundation

struct HAHistoryPoint: Decodable {
    var entityID: String?
    var state: String
    var lastChanged: String

    private enum CodingKeys: String, CodingKey {
        case entityID = "entity_id", state, lastChanged = "last_changed"
    }
}
