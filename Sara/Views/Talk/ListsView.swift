import SwiftData
import SwiftUI

/// All lists: open ones and closed ones (taken off the panel but kept). Swipe a closed list to bring it back or delete it.
struct ListsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ListItem.created) private var items: [ListItem]

    /// List names in the order they were started.
    private var names: [String] {
        var seen = Set<String>()
        return items.map(\.list).filter { seen.insert($0).inserted }
    }

    private func items(of name: String) -> [ListItem] { items.filter { $0.list == name } }
    private func closed(_ name: String) -> Date? { items(of: name).first?.closed }

    var body: some View {
        List {
            if names.isEmpty { Text("No lists yet").foregroundStyle(.secondary) }
            let open = names.filter { closed($0) == nil }
            if !open.isEmpty {
                Section("Open") { ForEach(open, id: \.self) { row($0) } }
            }
            let done = names.filter { closed($0) != nil }.sorted { closed($0)! > closed($1)! }
            if !done.isEmpty {
                Section("Closed") {
                    ForEach(done, id: \.self) { name in
                        row(name)
                            .swipeActions {
                                Button("Delete", role: .destructive) { items(of: name).forEach(context.delete) }
                                Button("Back to the panel") {
                                    items(of: name).forEach { $0.closed = nil }
                                    Panel.addList(name)
                                }
                                .tint(Theme.teal)
                            }
                    }
                }
            }
        }
        .navigationTitle("Lists")
    }

    private func row(_ name: String) -> some View {
        NavigationLink {
            List(items(of: name)) { item in
                Label { Text(verbatim: item.text).strikethrough(item.done) }
                    icon: { Image(systemName: item.done ? "checkmark.circle.fill" : "circle") }
            }
            .navigationTitle(Text(verbatim: name))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                if let date = closed(name) {
                    Text("Closed \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
