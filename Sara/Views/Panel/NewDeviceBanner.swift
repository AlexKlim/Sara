import SwiftUI

/// A device that appeared in Home Assistant: add it to the panel as its own block, or skip it.
struct NewDeviceBanner: View {
    let device: NewDevice

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(Theme.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("New device: \(device.name)").font(.system(size: 18, weight: .semibold))
                if let area = device.area { Text(verbatim: area).font(.system(size: 15)).foregroundStyle(Theme.secondary) }
            }
            Spacer()
            Button("Skip") { NewDevices.shared.skip(device) }
                .buttonStyle(.bordered).tint(Theme.secondary)
            Button("Add to panel") { Task { await NewDevices.shared.add(device) } }
                .buttonStyle(.borderedProminent).tint(Theme.teal)
        }
        .font(.system(size: 17))
        .padding(.vertical, 14).padding(.horizontal, 20)
        .card(padding: 0)
    }
}
