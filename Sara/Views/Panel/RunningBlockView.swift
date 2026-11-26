import SwiftUI

/// Devices that are working right now (printer, washer): progress, time left, finish time.
/// A washer that finished but is still on shows "Done" until it is switched off. Devices that are idle are hidden, and so is the whole block when nothing runs.
struct RunningBlockView: View {
    let block: PanelBlock
    let home: Home
    /// Phone: cards side by side, each with its time and progress under the name.
    var columns = 1
    @Environment(\.compactPanel) private var compact

    var body: some View {
        let running = block.items.enumerated().filter { home.isRunning($0.element) || home.isWaiting($0.element) }
        if !running.isEmpty {
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                Text(block.title).blockTitle(size: compact ? 13 : 15)
                if compact {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                        ForEach(running, id: \.element.id) { index, item in
                            compactCard(item, accent: Theme.accents[index % Theme.accents.count])
                        }
                    }
                } else {
                    ForEach(running, id: \.element.id) { index, item in
                        card(item, accent: Theme.accents[index % Theme.accents.count])
                    }
                }
            }
        }
    }

    private func compactCard(_ item: PanelItem, accent: Color) -> some View {
        let progress = home.number(item.progress)
        let minutes = home.minutesLeft(item.entity)
        let value = home.isWaiting(item) ? String(localized: "Done") : progress.map { ($0 / 100).formatted(.percent.precision(.fractionLength(0))) } ?? minutes.map(Self.duration)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: item.icon ?? "timer")
                    .font(.system(size: 18)).foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.15), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(home.name(item)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if !home.isWaiting(item), let end = end(item) {
                        Text("Until \(end.formatted(date: .omitted, time: .shortened))").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    } else if let detail = detail(item) {
                        Text(verbatim: detail).font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                }
            }
            HStack(spacing: 10) {
                if let progress {
                    ProgressView(value: min(max(progress, 0), 100), total: 100).tint(accent).scaleEffect(y: 1.5)
                } else {
                    if let phase = phase(item) { Text(verbatim: phase).font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(1) }
                    Spacer(minLength: 0)
                }
                if let value { Text(verbatim: value).font(.system(size: 15, weight: .semibold)).monospacedDigit() }
            }
        }
        .foregroundStyle(Theme.text)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
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
                    if let detail = detail(item) {
                        Text(verbatim: detail).font(.system(size: 15)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if let progress {
                    Text((progress / 100).formatted(.percent.precision(.fractionLength(0)))).font(.system(size: 32, weight: .semibold))
                } else if home.isWaiting(item) {
                    Text("Done").font(.system(size: 32, weight: .semibold))
                } else if let minutes {
                    Text(Self.duration(minutes)).font(.system(size: 32, weight: .semibold))
                }
            }
            if let progress {
                ProgressView(value: min(max(progress, 0), 100), total: 100).tint(accent).scaleEffect(y: 2.5)
            }
            if !home.isWaiting(item), let end = end(item) {
                let time = end.formatted(date: .omitted, time: .shortened)
                Group {
                    if let phase = phase(item) {
                        Text("\(phase), done at \(time)")
                    } else {
                        Text("Done at \(time)")
                    }
                }
                .font(.system(size: 16)).foregroundStyle(Theme.secondary)
            }
        }
        .foregroundStyle(Theme.text)
        .card()
    }

    /// The program or file name. A bare number (a program phase code) means nothing to a person.
    private func detail(_ item: PanelItem) -> String? {
        guard let detail = home.state(item.detail), !["unknown", "unavailable"].contains(detail), Double(detail) == nil else { return nil }
        return Bundle.main.localizedString(forKey: "program." + detail, value: detail, table: nil)
    }

    private func end(_ item: PanelItem) -> Date? {
        home.date(item.end) ?? home.minutesLeft(item.entity).map { .now + $0 * 60 }
    }

    private func phase(_ item: PanelItem) -> String? {
        guard let base = item.base else { return nil }
        guard let value = item.entity.hasSuffix("remaining_drying_time") ? "Drying"
                : ["cyclephase", "cycle_phase", "current_stage"].lazy.compactMap({ home.state("sensor." + base + $0) }).first,
              !["unknown", "unavailable"].contains(value.lowercased()) else { return nil }
        return Bundle.main.localizedString(forKey: "phase." + value, value: value, table: nil)
    }

    /// 72 -> "1 h 12 min" (localized).
    static func duration(_ minutes: Double) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
