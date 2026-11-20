import SwiftUI

/// One device, such as a fridge: setpoints with − and + (and the current value from the sensor of the same name),
/// sensor values, doors and switches.
struct DeviceBlockView: View {
    let block: PanelBlock
    let home: Home
    @State private var pending: [String: Double] = [:]
    @State private var failed: Set<String> = []

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
    }

    @ViewBuilder private func row(_ item: PanelItem) -> some View {
        let id = item.entity
        switch PanelItem.domain(id) {
        case "number", "input_number": setpoint(item)
        case "binary_sensor":
            let on = home.isOn(id)
            let icon = isOpening(id) ? (on ? "door.left.hand.open" : "door.left.hand.closed") : "sensor"
            line(item, icon: icon, alert: on) {
                Text(verbatim: isOpening(id) ? String(localized: on ? "door.open" : "door.closed") : String(localized: on ? "On" : "Off"))
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(on ? Theme.amber : Theme.secondary)
            }
        case "switch", "input_boolean":
            line(item, icon: "power", alert: false) {
                Toggle(isOn: Binding(get: { home.isOn(id) }, set: { _ in Task { await home.toggle(id) } })) {}
                    .labelsHidden().tint(Theme.amber)
            }
        default:
            line(item, icon: unit(id) == "°C" ? "thermometer.medium" : "gauge.medium", alert: false) {
                Text(verbatim: text(id, home.number(id))).font(.system(size: 22, weight: .semibold)).monospacedDigit()
            }
        }
    }

    private func setpoint(_ item: PanelItem) -> some View {
        let id = item.entity
        let name = name(item)
        let value = pending[id] ?? home.number(id)
        let current = home.number("sensor." + PanelItem.objectID(id))
        return HStack(spacing: 14) {
            Image(systemName: unit(id) == "°C" ? "thermometer.medium" : "slider.horizontal.3").font(.system(size: 22))
                .foregroundStyle(Theme.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).font(.system(size: 18, weight: .medium))
                if failed.contains(id) {
                    Text("Couldn't change the setting").font(.system(size: 15)).foregroundStyle(Theme.amber)
                } else if let current {
                    Text("Now \(text(id, current))").font(.system(size: 15)).foregroundStyle(Theme.secondary)
                }
            }
            Spacer()
            if let value {
                TargetStepper(
                    id: id, name: name, value: value, home: home,
                    pending: Binding(get: { pending[id] }, set: { pending[id] = $0 }),
                    failed: Binding(get: { failed.contains(id) }, set: { if $0 { failed.insert(id) } else { failed.remove(id) } }),
                    format: { text(id, $0) },
                    reported: { home.number(id) },
                    send: { try await home.setNumber(id, $0) })
            }
        }
    }

    private func line(_ item: PanelItem, icon: String, alert: Bool, @ViewBuilder value: () -> some View) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(alert ? Theme.amber : Theme.secondary)
            Text(verbatim: name(item)).font(.system(size: 18, weight: .medium))
            Spacer()
            value()
        }
    }

    /// Without the device name: in the "Fridge" block, "Fridge Freezer door" is "Freezer door".
    private func name(_ item: PanelItem) -> String {
        let name = home.name(item)
        guard item.name == nil, name.hasPrefix(block.title + " ") else { return name }
        return String(name.dropFirst(block.title.count + 1)).capitalizedFirst
    }

    private func unit(_ id: String) -> String? { home.attribute(id, "unit_of_measurement") as? String }

    private func text(_ id: String, _ value: Double?) -> String {
        guard let value else { return "-" }
        if unit(id) == "°C" { return value.degrees }
        return value.formatted(.number.precision(.fractionLength(0...1))) + (unit(id).map { " " + $0 } ?? "")
    }

    private func isOpening(_ id: String) -> Bool {
        ["door", "window", "opening", "garage_door"].contains(home.attribute(id, "device_class") as? String ?? "")
    }
}
