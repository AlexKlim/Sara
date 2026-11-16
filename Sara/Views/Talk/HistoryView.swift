import SwiftData
import SwiftUI

/// All past conversations, newest first.
struct HistoryView: View {
    // ponytail: loads the whole history, add a fetch limit or paging when it grows large
    @Query(sort: \Turn.date, order: .reverse) private var turns: [Turn]

    /// Turns grouped into conversations, newest conversation first, turns inside oldest first.
    private var chats: [[Turn]] {
        turns.reduce(into: [[Turn]]()) { chats, turn in
            if chats.last?.first?.chatID == turn.chatID { chats[chats.count - 1].insert(turn, at: 0) } else { chats.append([turn]) }
        }
    }

    var body: some View {
        List {
            ForEach(chats, id: \.first!.chatID) { chat in
                Section {
                    ForEach(chat) { TurnRow(turn: $0) }
                } header: {
                    Text(chat[0].date, format: .dateTime.day().month().hour().minute())
                }
            }
        }
        .navigationTitle("History")
    }
}
