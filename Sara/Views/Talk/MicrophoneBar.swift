import AVFoundation
import SwiftUI

/// On a Mac an iPad app hears only the system input and can't list the others,
/// so the dialog shows which microphone Sara hears and opens the system setting to change it.
struct MicrophoneBar: View {
    let listening: Bool
    @State private var name: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            if let name { Label("Microphone: \(name)", systemImage: "mic").foregroundStyle(Theme.secondary) }
            Button("Change") { openURL(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension?input")!) }
                .tint(Theme.teal)
        }
        .font(.system(size: 14))
        .onChange(of: listening, initial: true) { readName() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(on: RunLoop.main)) { _ in
            readName()
        }
    }

    private func readName() {
        name = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName
    }
}
