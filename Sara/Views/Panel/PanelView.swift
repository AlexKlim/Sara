import SwiftUI

/// The main wall panel screen from the design: header, blocks in two columns, the current conversation at the bottom.
struct PanelView: View {
    let home: Home
    let panel: Panel
    /// Last exchange of the conversation in progress. nil once it is closed.
    let lastTurn: Turn?
    /// Wake word listening is on.
    let listening: Bool
    let onTalk: () -> Void
    let onSettings: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let wide = sizeClass == .regular
        VStack(spacing: 28) {
            HeaderView(home: home, listening: listening, onTalk: onTalk, onSettings: onSettings)
            if let device = NewDevices.shared.found.first { NewDeviceBanner(device: device) }
            if panel.blocks.isEmpty {
                Spacer()
                Text("Set up the panel in Settings").foregroundStyle(Theme.secondary)
                Spacer()
            } else {
                if home.offline {
                    Label("No connection to Home Assistant", systemImage: "wifi.exclamationmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.amber)
                        .padding(.vertical, 12).padding(.horizontal, 20)
                        .background(Theme.amberBackground, in: .capsule)
                        .overlay(Capsule().stroke(Theme.amberBorder))
                }
                Group {
                    if wide {
                        GeometryReader { geometry in
                            HStack(alignment: .top, spacing: 28) {
                                column(panel.blocks.filter { $0.column == 0 }).frame(width: (geometry.size.width - 28) * 7 / 12)
                                column(panel.blocks.filter { $0.column != 0 }, alarms: true)
                            }
                        }
                    } else {
                        column(panel.blocks, alarms: true)
                    }
                }

            }
            if let lastTurn { footer(lastTurn) }
        }
        .padding(wide ? 40 : 16)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
    }

    /// `alarms`: this column starts with the timers and alarms that are set.
    private func column(_ blocks: [PanelBlock], alarms: Bool = false) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if alarms { AlarmsBlockView(alarms: .shared) }
                ForEach(blocks) { block(for: $0) }
            }
        }
        .scrollIndicators(.hidden)
    }

    /// Without Home Assistant its states are unknown, not off: such blocks fade and take no taps.
    /// Yandex devices, timers and the app's own lists keep working.
    private func block(for block: PanelBlock) -> some View {
        let usesHomeAssistant = block.items.contains { block.kind == .list ? $0.entity.hasPrefix("todo.") : !$0.entity.hasPrefix("yandex.") }
        let unreachable = home.offline && usesHomeAssistant
        return blockContent(block)
            .saturation(unreachable ? 0 : 1)
            .opacity(unreachable ? 0.4 : 1)
            .allowsHitTesting(!unreachable)
    }

    @ViewBuilder private func blockContent(_ block: PanelBlock) -> some View {
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
                TodoBlockView(entity: todo, title: block.title, home: home)
            } else {
                ListBlockView(name: block.title)
            }
        }
    }

    /// The conversation in progress, one line. Tap to open it.
    private func footer(_ turn: Turn) -> some View {
        Button(action: onTalk) {
            HStack(spacing: 16) {
                Image(systemName: "mic").foregroundStyle(Theme.teal)
                Text(verbatim: "«\(turn.user)»").foregroundStyle(Theme.secondary).lineLimit(1)
                Text(verbatim: turn.reply ?? "...").fontWeight(.medium).lineLimit(1)
                Spacer()
                Text(turn.date.formatted(.relative(presentation: .named))).font(.system(size: 15)).foregroundStyle(Theme.secondary)
            }
            .font(.system(size: 18))
            .padding(.horizontal, 24)
            .frame(height: 76)
            .background(Theme.card, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border))
        }
        .buttonStyle(.plain)
    }
}
