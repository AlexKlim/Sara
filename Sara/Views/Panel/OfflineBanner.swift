import SwiftUI

/// Home Assistant can't be reached: its blocks fade, and this says why.
struct OfflineBanner: View {
    var body: some View {
        Label("No connection to Home Assistant", systemImage: "wifi.exclamationmark")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Theme.amber)
            .padding(.vertical, 12).padding(.horizontal, 20)
            .background(Theme.amberBackground, in: .capsule)
            .overlay(Capsule().stroke(Theme.amberBorder))
    }
}
