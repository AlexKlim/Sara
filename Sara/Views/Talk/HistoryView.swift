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
        .refreshable { reload() }
    }

    private func loadOlder() {
        guard let page = fetch(Self.page, before: turns.last?.date ?? .distantFuture) else { return }
        turns += page
    }

    /// Picks up turns that iCloud brought while History was open, keeping as many rows as were loaded.
    private func reload() {
        guard let page = fetch(max(turns.count, Self.page), before: .distantFuture) else { return }
        turns = page
    }

    /// Up to `count` turns before the date, newest first; also sets whether older ones remain.
    private func fetch(_ count: Int, before: Date) -> [Turn]? {
        var descriptor = FetchDescriptor<Turn>(predicate: #Predicate { $0.date < before }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = count + 1
        guard let fetched = try? context.fetch(descriptor) else { return nil }
        hasOlder = fetched.count > count
        return Array(fetched.prefix(count))
    }
}
