import SwiftUI

/// "Printer is done" card over the panel. Closes by tap or by itself after 5 minutes.
struct DoneAlertView: View {
    let name: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Theme.deepBackground.opacity(0.74).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "checkmark").font(.system(size: 40, weight: .semibold)).foregroundStyle(Theme.amber)
                    .frame(width: 96, height: 96).background(Theme.amberBackground, in: .circle)
                Text("\(name) is done").font(.system(size: 44, weight: .semibold)).multilineTextAlignment(.center)
                Button(action: onClose) {
                    Text("OK").font(.system(size: 20, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 60)
                        .background(Theme.amber, in: .rect(cornerRadius: 16)).foregroundStyle(Color(hex: 0x1A1206))
                }
                .buttonStyle(.plain)
                Text("Closes by itself in 5 minutes").font(.system(size: 15)).foregroundStyle(Theme.secondary)
            }
            .padding(48)
            .frame(maxWidth: 640)
            .background(Theme.card, in: .rect(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.ring))
            .padding(24)
        }
        .foregroundStyle(Theme.text)
        .task {
            try? await Task.sleep(for: .seconds(300))
            onClose()
        }
    }
}
