import Foundation

struct HAArea: Decodable, Equatable {
    var id: String
    var name: String

    private enum CodingKeys: String, CodingKey {
        case id = "area_id", name
    }
}
