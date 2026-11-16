import Foundation
import SwiftData

/// One exchange: what the user said, what Sara did, what she answered, and how long it took.
/// All properties have defaults, as CloudKit sync requires.
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

    // ponytail: the current conversation is always among the newest turns; a chat longer than 50 turns shows its last 50.
    static var latest: FetchDescriptor<Turn> {
        var descriptor = FetchDescriptor<Turn>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 50
        return descriptor
    }
}
