import Foundation

struct HATodoItem: Decodable, Equatable {
    var uid: String
    var summary: String
    var status: String

    var done: Bool { status == "completed" }
}
