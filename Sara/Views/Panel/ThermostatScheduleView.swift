import SwiftUI

/// A DEVI thermostat's own weekly schedule, opened from its row on the panel: comfort periods per day on a 24-hour bar.
struct ThermostatScheduleView: View {
    let name: String
    let serial: String
    let home: Home
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let schedule = home.state(DeviSchedule.sensor(serial: serial)).flatMap(DeviSchedule.init(json:))
        VStack(alignment: .leading, spacing: 24) {
            header
            summary
            if let schedule {
                VStack(spacing: 14) {
                    ForEach(0..<7, id: \.self) { day in row(day, schedule.days[day]) }
                    hours
                }
            }
            Text("To change it, ask Sara.").font(.system(size: 16)).foregroundStyle(Theme.secondary)
        }
        .padding(32)
        .frame(idealWidth: 760, maxWidth: 760)
        .foregroundStyle(Theme.text)
        .background(Theme.sheet)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("Schedule").font(.system(size: 28, weight: .semibold))
            Text(verbatim: name).font(.system(size: 18)).foregroundStyle(Theme.secondary)
            Spacer()
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 48, height: 48)
                .background(Theme.card, in: .circle)
                .overlay(Circle().stroke(Theme.ring))
                .buttonStyle(.plain)
        }
    }

    private var summary: some View {
        let comfort = home.state("number.devireg_\(serial)_t_comfort").flatMap(Double.init)
        let economy = home.state("number.devireg_\(serial)_t_economy").flatMap(Double.init)
        let active = home.state("select.devireg_\(serial)_control_mode") == "SCHEDULE"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 24) {
                if let comfort { Label { Text("Comfort \(comfort.degrees)") } icon: { swatch(Theme.amber) } }
                if let economy { Label { Text("Economy \(economy.degrees)") } icon: { swatch(Theme.border) } }
            }
            .font(.system(size: 20, weight: .medium))
            Text(active ? "The thermostat follows this schedule." : "The schedule is off: the thermostat keeps one temperature.")
                .font(.system(size: 16)).foregroundStyle(active ? Theme.secondary : Theme.amber)
        }
    }

    private func row(_ day: Int, _ periods: [Range<Int>]) -> some View {
        // Calendar weekday symbols start on Sunday, the schedule on Monday.
        let symbol = Calendar.current.shortStandaloneWeekdaySymbols[(day + 1) % 7]
        return HStack(spacing: 16) {
            Text(verbatim: symbol.capitalized).font(.system(size: 18, weight: .medium)).frame(width: 44, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.card)
                    ForEach(periods, id: \.lowerBound) { period in
                        Capsule().fill(Theme.amber)
                            .frame(width: geometry.size.width * CGFloat(period.count) / 1440)
                            .offset(x: geometry.size.width * CGFloat(period.lowerBound) / 1440)
                    }
                }
            }
            .frame(height: 22)
            Group {
                if periods.isEmpty {
                    Text("Economy all day").foregroundStyle(Theme.secondary)
                } else {
                    Text(verbatim: periods.map { "\(Self.time($0.lowerBound))-\(Self.time($0.upperBound))" }.joined(separator: ", "))
                }
            }
            .font(.system(size: 16)).monospacedDigit().frame(width: 230, alignment: .leading)
        }
    }

    /// Hour marks under the bars, aligned with them.
    private var hours: some View {
        HStack(spacing: 16) {
            Color.clear.frame(width: 44, height: 1)
            GeometryReader { geometry in
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Text(verbatim: "\(hour)").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        .fixedSize()
                        .position(x: geometry.size.width * CGFloat(hour) / 24, y: 8)
                }
            }
            .frame(height: 16)
            Color.clear.frame(width: 230, height: 1)
        }
    }

    private func swatch(_ color: Color) -> some View { Circle().fill(color).frame(width: 12, height: 12) }

    private static func time(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
}
