import SwiftUI

/// Timers (live countdown), alarms and scheduled commands (time of day) that are set. Hidden when there are none.
struct AlarmsBlockView: View {
    let alarms: Alarms

    var body: some View {
        if !alarms.pending.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Timers and alarms").blockTitle()
                VStack(spacing: 0) {
                    ForEach(alarms.pending) { alarm in
                        HStack(spacing: 14) {
                            Image(systemName: alarm.isCommand ? "clock.arrow.circlepath" : alarm.isTimer ? "timer" : "alarm").font(.system(size: 20)).foregroundStyle(Theme.amber)
                            Text(verbatim: alarm.label).font(.system(size: 18, weight: .medium)).lineLimit(1)
                            Spacer()
                            Group {
                                if alarm.isTimer && !alarm.isCommand {
                                    Text(timerInterval: Date.now...max(alarm.fireDate, .now), countsDown: true)
                                } else {
                                    Text(alarm.fireDate, format: .dateTime.hour().minute())
                                }
                            }
                            .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                            Button("Cancel", systemImage: "xmark.circle.fill") { alarms.cancel(alarm.id) }
                                .labelStyle(.iconOnly).font(.title2).foregroundStyle(Theme.muted)
                                .buttonStyle(.plain)
                        }
                        .padding(.vertical, 14)
                        if alarm.id != alarms.pending.last?.id { Divider().overlay(Theme.border) }
                    }
                }
                .foregroundStyle(Theme.text)
                .card(padding: 24)
            }
        }
    }
}
