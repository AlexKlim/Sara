import Foundation

struct HAEntityEntry: Decodable, Equatable {
    var id: String
    var device: String?
    var area: String?
    var hidden: Bool?
    var category: Int?
    var platform: String?

    private enum CodingKeys: String, CodingKey {
        case id = "ei", device = "di", area = "ai", hidden = "hb", category = "ec", platform = "pl"
    }
}
