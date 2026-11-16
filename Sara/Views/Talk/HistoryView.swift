import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @State private var turns: [Turn] = []
    @State private var hasOlder = false
    private static let page = 200

    /// Newest conversation first, turns inside oldest first.
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
            if hasOlder {
                Button("Show older") { loadOlder() }
            }
        }
        .navigationTitle("History")
        .task { if turns.isEmpty { loadOlder() } }
    }

    private func loadOlder() {
        var descriptor = FetchDescriptor<Turn>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchOffset = turns.count
        descriptor.fetchLimit = Self.page + 1
        let fetched = (try? context.fetch(descriptor)) ?? []
        hasOlder = fetched.count > Self.page
        turns += fetched.prefix(Self.page)
    }
}
