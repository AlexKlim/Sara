import Foundation

struct HAMessage<Payload: Decodable>: Decodable {
    var id: Int?
    var type: String
    var success: Bool?
    var result: Payload?
    var event: Payload?
}
