import SwiftUI

/// A Home Assistant to-do list on the panel (e.g. the shopping list shared with Alice).
/// Same look as app lists; checking an item off updates it in Home Assistant.
struct TodoBlockView: View {
    let entity: String
    /// Shown instead of the list's Home Assistant name, if set.
    let title: String
    let home: Home

    private var items: [HATodoItem] { home.todoItems[entity] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: title.isEmpty ? home.attribute(entity, "friendly_name") as? String ?? entity : title).blockTitle()
            VStack(spacing: 0) {
                if items.isEmpty {
                    Text("Empty").foregroundStyle(Theme.secondary).padding(.vertical, 12)
                }
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    ChecklistRow(text: item.summary, done: item.done) {
                        Task { await home.setTodo(entity, item: item.uid, done: !item.done) }
                    }
                    if index < items.count - 1 { Divider().overlay(Theme.border) }
                }
            }
            .foregroundStyle(Theme.text)
            .card(padding: 24)
        }
        // Reload while on screen, and when the list's item count (its state) changes.
        .task(id: home.state(entity)) {
            while !Task.isCancelled {
                await home.loadTodo(entity)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}
