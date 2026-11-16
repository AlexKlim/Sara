import SwiftUI

/// One exchange in the chat list: the phrase, what Sara did, her answer and the timing.
struct TurnRow: View {
    let turn: Turn

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(turn.user).foregroundStyle(.secondary)
            ForEach(turn.actions, id: \.self) { action in
                Label(action, systemImage: "checkmark").font(.caption).foregroundStyle(.teal)
            }
            Text(turn.reply ?? "...")
            if let total = turn.totalSeconds, !turn.claudeSeconds.isEmpty {
                let claude = turn.claudeSeconds.map(seconds).joined(separator: " + ")
                let ha = seconds(turn.haSeconds)
                Group {
                    if let first = turn.firstTextSeconds {
                        Text("\(seconds(total)) s, first words after \(seconds(first)) s (Claude \(claude), HA \(ha))")
                    } else {
                        Text("\(seconds(total)) s (Claude \(claude), HA \(ha))")
                    }
                }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// 1.234 -> "1.2" (or "1,2" in Russian).
    private func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
