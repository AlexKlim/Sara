import SwiftUI

/// Thermostats: target temperature with − and + buttons, and the current one. The icon glows while heating.
struct ClimateBlockView: View {
    let block: PanelBlock
    let home: Home
    @State private var pending: [String: Double] = [:]
    @State private var failed: Set<String> = []
    /// The thermostat whose own weekly schedule is open.
    @State private var scheduleOf: PanelItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(block.title).blockTitle()
            VStack(spacing: 0) {
                ForEach(block.items) { item in
                    row(item).padding(.vertical, 14)
                    if item.id != block.items.last?.id { Divider().overlay(Theme.border) }
                }
            }
            .foregroundStyle(Theme.text)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .padding(.vertical, 4)
            .card(padding: 0)
        }
        .sheet(item: $scheduleOf) { item in
            if let serial = DeviSchedule.serial(of: item.entity) {
                ThermostatScheduleView(name: home.name(item), serial: serial, home: home)
                    .presentationSizing(.fitted)
                    .presentationCornerRadius(28)
            }
        }
    }

    private func row(_ item: PanelItem) -> some View {
        let id = item.entity
        let name = home.name(item)
        let target = pending[id] ?? home.attribute(id, "temperature") as? Double
        let heating = home.isHeating(id, target: target)
        let status = status(id, heating: heating, target: target)
        // A DEVI thermostat keeps its own weekly schedule: then the row opens it.
        let hasSchedule = DeviSchedule.serial(of: id).map { home.state(DeviSchedule.sensor(serial: $0)) != nil } ?? false
        let info = HStack(spacing: 14) {
            Image(systemName: "thermometer.medium").font(.system(size: 22))
                .foregroundStyle(heating ? Theme.amber : Theme.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(verbatim: name).font(.system(size: 18, weight: .medium))
                    if hasSchedule { Image(systemName: "calendar").font(.system(size: 15)).foregroundStyle(Theme.muted) }
                }
                if let status {
                    Text(status).font(.system(size: 15)).foregroundStyle(heating || failed.contains(id) ? Theme.amber : Theme.secondary)
                }
            }
        }
        return HStack(spacing: 14) {
            if hasSchedule {
                Button { scheduleOf = item } label: { info.contentShape(.rect) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the schedule")
            } else {
                info
            }
            Spacer()
            if let target, id.hasPrefix("climate.") {
                TargetStepper(
                    id: id, name: name, value: target, home: home,
                    pending: Binding(get: { pending[id] }, set: { pending[id] = $0 }),
                    failed: Binding(get: { failed.contains(id) }, set: { if $0 { failed.insert(id) } else { failed.remove(id) } }),
                    format: \.degreesTenths,
                    reported: { home.attribute(id, "temperature") as? Double },
                    send: { try await home.setTemperature(id, $0) })
            } else if let target {
                Text(verbatim: target.degreesTenths).font(.system(size: 28, weight: .semibold)).monospacedDigit()
            }
        }
    }

    private func status(_ id: String, heating: Bool, target: Double?) -> LocalizedStringKey? {
        if failed.contains(id) { return "Couldn't change the temperature" }
        guard let current = home.attribute(id, "current_temperature") as? Double else { return nil }
        let now = current.degrees
        if home.state(id) == "off" { return "Now \(now), off" }
        if heating { return "Now \(now), heating" }
        if let target, current > target + 0.5 { return "Now \(now), cooling" }
        return "Now \(now), holding"
    }
}
