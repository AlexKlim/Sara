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
                if home.offline { OfflineBanner() }
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
                ForEach(blocks) { BlockView(block: $0, home: home) }
            }
        }
        .scrollIndicators(.hidden)
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
