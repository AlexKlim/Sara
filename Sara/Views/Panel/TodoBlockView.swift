import SwiftUI

struct TodoBlockView: View {
    let entity: String
    let title: String
    let home: Home

    private var items: [HATodoItem] { home.todoItems[entity] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: title.isEmpty ? home.attribute(entity, "friendly_name") as? String ?? entity : title).blockTitle()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) {
                    if !items.isEmpty, items.allSatisfy(\.done) {
                        Button("Clear the list", systemImage: "xmark.circle.fill") { Task { await home.clearDone(entity) } }
                            .labelStyle(.iconOnly).font(.title2).foregroundStyle(Theme.muted)
                            .buttonStyle(.plain)
                    }
                }
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
        .task(id: home.state(entity)) {
            while !Task.isCancelled {
                await home.loadTodo(entity)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}
