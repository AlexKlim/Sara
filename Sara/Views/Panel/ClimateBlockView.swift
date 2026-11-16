import SwiftUI

/// Thermostats: current and target temperature. The icon glows while heating.
struct ClimateBlockView: View {
    let block: PanelBlock
    let home: Home

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(block.title).blockTitle()
            VStack(spacing: 0) {
                ForEach(block.items) { item in
                    HStack(spacing: 14) {
                        Image(systemName: "thermometer.medium").font(.system(size: 20))
                            .foregroundStyle(home.attribute(item.entity, "hvac_action") as? String == "heating" ? Theme.amber : Theme.secondary)
                        Text(home.name(item)).font(.system(size: 18, weight: .medium))
                        Spacer()
                        if let target = home.attribute(item.entity, "temperature") as? Double {
                            Text("target \(Self.degrees(target))").font(.system(size: 15)).foregroundStyle(Theme.secondary)
                        }
                        Text(verbatim: (home.attribute(item.entity, "current_temperature") as? Double).map(Self.degrees) ?? "-")
                            .font(.system(size: 28, weight: .semibold)).frame(minWidth: 64, alignment: .trailing)
                    }
                    .padding(.vertical, 16)
                    if item.id != block.items.last?.id { Divider().overlay(Theme.border) }
                }
            }
            .foregroundStyle(Theme.text)
            .card(padding: 24)
        }
    }

    private static func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }
}
