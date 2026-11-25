import SwiftUI

/// One block of the panel in its own view: room tiles, a slider, running devices, thermostats, a device or a list.
/// Without Home Assistant its states are unknown, so a block that depends on it fades.
struct BlockView: View {
    let block: PanelBlock
    let home: Home
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        content.unreachable(home.offline && block.usesHomeAssistant)
    }

    @ViewBuilder private var content: some View {
        switch block.kind {
        case .room:
            VStack(alignment: .leading, spacing: 12) {
                Text(block.title).blockTitle()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: sizeClass == .regular ? 3 : 2), spacing: 12) {
                    ForEach(block.items) { TileView(item: $0, home: home) }
                }
            }
        case .slider:
            ForEach(block.items) { SliderBlockView(title: block.title, item: $0, home: home) }
        case .running:
            RunningBlockView(block: block, home: home)
        case .climate:
            ClimateBlockView(block: block, home: home)
        case .device:
            DeviceBlockView(block: block, home: home)
        case .list:
            if let todo = block.items.first?.entity, todo.hasPrefix("todo.") {
                // The state counts only open items: a list at 0 may still hold checked ones, so it hides only once loaded empty.
                let loaded = home.todoItems[todo]
                if home.state(todo) != "0" || loaded?.isEmpty == false {
                    TodoBlockView(entity: todo, title: block.title, home: home)
                } else if loaded == nil {
                    Color.clear.frame(height: 0).task { await home.loadTodo(todo) }
                }
            } else {
                ListBlockView(name: block.title)
            }
        }
    }
}
