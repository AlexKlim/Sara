import SwiftUI

/// Night mode: a dim clock on black. Sara answers in text only. Tap to wake the panel.
struct NightView: View {
    let home: Home
    let panel: Panel
    let endHour: Int

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack {
                Spacer()
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 220, weight: .light)).tracking(-8).monospacedDigit()
                    .minimumScaleFactor(0.3).lineLimit(1)
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirst)
                    .font(.system(size: 26)).foregroundStyle(Color(hex: 0x565D68))
                Spacer()
                HStack {
                    if let alarm = Alarms.shared.pending.first {
                        Label { Text(verbatim: "\(alarm.label) \(alarm.fireDate.formatted(date: .omitted, time: .shortened))") }
                            icon: { Image(systemName: alarm.isTimer ? "timer" : "alarm") }
                        Spacer()
                    }
                    if let item = running.first, let minutes = home.minutesLeft(item.entity) {
                        Text(verbatim: "\(home.name(item)): ") + Text("Remaining \(RunningBlockView.duration(minutes))")
                    }
                    Spacer()
                    Text("Night mode until \(Self.hour(endHour)) · Sara answers in text")
                }
                .font(.system(size: 18)).foregroundStyle(Theme.muted)
            }
            .padding(56)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .foregroundStyle(Color(hex: 0x6B7380))
        }
    }

    private var running: [PanelItem] {
        panel.blocks.filter { $0.kind == .running }.flatMap(\.items).filter(home.isRunning)
    }

    /// 10 -> "10:00" in the device's time format.
    static func hour(_ hour: Int) -> String {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)?.formatted(date: .omitted, time: .shortened) ?? "\(hour):00"
    }
}
