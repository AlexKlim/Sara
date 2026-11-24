import Foundation

struct HADevice: Decodable, Equatable {
    var id: String
    var name: String?
    var nameByUser: String?
    var areaID: String?
    var disabledBy: String?
    var entryType: String?
    var createdAt: Double?

    var displayName: String { nameByUser ?? name ?? "" }

    private enum CodingKeys: String, CodingKey {
        case id, name, nameByUser = "name_by_user", areaID = "area_id", disabledBy = "disabled_by", entryType = "entry_type",
             createdAt = "created_at"
    }
}
