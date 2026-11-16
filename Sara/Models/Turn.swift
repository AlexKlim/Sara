import Foundation
import SwiftData

/// One exchange: what the user said, what Sara did, what she answered, and how long it took.
/// Stored on the device. All properties have defaults so the model can sync through CloudKit later.
@Model final class Turn {
    var id = UUID()
    /// Turns of one conversation (one chat window) share this id.
    var chatID = UUID()
    var date = Date.now
    var user = ""
    var reply: String?
    var actions: [String] = []
    var claudeSeconds: [Double] = []
    var haSeconds: Double = 0
    var firstTextSeconds: Double?
    var totalSeconds: Double?

    init(chatID: UUID, user: String) {
        self.chatID = chatID
        self.user = user
    }
}
