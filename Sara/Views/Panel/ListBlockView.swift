import SwiftData
import SwiftUI

/// A list on the panel. Tap an item to check it off (it stays, struck through) or to uncheck it.
/// When everything is checked, an ✕ next to the title closes the list.
struct ListBlockView: View {
    let name: String
    @Environment(\.modelContext) private var context
    // ponytail: loads all list items and filters by name, a predicate per list if lists grow large
    @Query(sort: \ListItem.created) private var allItems: [ListItem]

    private var items: [ListItem] { allItems.filter { $0.list == name } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(verbatim: name).blockTitle()
                Spacer()
                if !items.isEmpty, items.allSatisfy(\.done) {
                    Button("Close the list", systemImage: "xmark.circle.fill", action: close)
                        .labelStyle(.iconOnly).font(.title2).foregroundStyle(Theme.muted)
                        .buttonStyle(.plain)
                }
            }
            VStack(spacing: 0) {
                if items.isEmpty {
                    Text("Empty").foregroundStyle(Theme.secondary).padding(.vertical, 12)
                }
                ForEach(items) { item in
                    ChecklistRow(text: item.text, done: item.done) { withAnimation { item.done.toggle() } }
                    if item.id != items.last?.id { Divider().overlay(Theme.border) }
                }
            }
            .foregroundStyle(Theme.text)
            .card(padding: 24)
        }
    }

    /// Takes the list off the panel. It is kept: Lists shows it, and Sara can read or reopen it.
    private func close() {
        withAnimation {
            items.forEach { $0.closed = .now }
            Panel.removeList(name)
        }
    }
}
