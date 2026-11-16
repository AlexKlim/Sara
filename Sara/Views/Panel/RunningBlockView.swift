import SwiftUI

/// Devices that are working right now (printer, washer): progress, time left, finish time.
/// Devices that are idle are hidden, and so is the whole block when nothing runs.
struct RunningBlockView: View {
    let block: PanelBlock
    let home: Home

    var body: some View {
        let running = block.items.enumerated().filter { home.isRunning($0.element) }
        if !running.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(block.title).blockTitle()
                ForEach(running, id: \.element.id) { index, item in
                    card(item, accent: Theme.accents[index % Theme.accents.count])
                }
            }
        }
    }

    private func card(_ item: PanelItem, accent: Color) -> some View {
        let progress = home.number(item.progress)
        let minutes = home.minutesLeft(item.entity)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: item.icon ?? "timer")
                    .font(.system(size: 22)).foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(accent.opacity(0.15), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(home.name(item)).font(.system(size: 19, weight: .semibold))
                    if let detail = home.state(item.detail), detail != "unknown" {
                        Text(verbatim: detail).font(.system(size: 15)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if let progress {
                    Text((progress / 100).formatted(.percent.precision(.fractionLength(0)))).font(.system(size: 32, weight: .semibold))
                } else if let minutes {
                    Text(Self.duration(minutes)).font(.system(size: 32, weight: .semibold))
                }
            }
            if let progress {
                ProgressView(value: min(max(progress, 0), 100), total: 100).tint(accent).scaleEffect(y: 2.5)
            }
            if let minutes {
                Group {
                    if let end = home.date(item.end) {
                        Text("Remaining \(Self.duration(minutes)), done at \(end.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Text("Remaining \(Self.duration(minutes))")
                    }
                }
                .font(.system(size: 16)).foregroundStyle(Theme.secondary)
            }
        }
        .foregroundStyle(Theme.text)
        .card()
    }

    /// 72 -> "1 h 12 min" (localized).
    static func duration(_ minutes: Double) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
