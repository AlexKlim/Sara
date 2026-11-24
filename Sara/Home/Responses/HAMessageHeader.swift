import Foundation

struct HAMessageHeader: Decodable {
    var id: Int?
    var type: String
    var success: Bool?
}
