import AVFoundation
import SwiftUI
import VisionKit

struct ScanConnectionView: View {
    let onConnect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cameraAllowed: Bool?
    @State private var link: SetupLink?
    @State private var notSaraCode = false

    var body: some View {
        NavigationStack {
            Group {
                if cameraAllowed == true && DataScannerViewController.isSupported {
                    QRScanner { text in
                        guard link == nil else { return }
                        link = SetupLink(payload: text)
                        notSaraCode = link == nil
                    }
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        Text(notSaraCode ? "This is not a Sara code." : "Point the camera at the code on the other device.")
                            .padding(12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(32)
                    }
                } else if cameraAllowed != nil {
                    Text("This device can't scan QR codes, or Sara has no access to the camera.")
                        .multilineTextAlignment(.center)
                        .padding(24)
                }
            }
            .navigationTitle("Scan connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }
        .task { cameraAllowed = await AVCaptureDevice.requestAccess(for: .video) }
        .alert("Connect to this home?", isPresented: Binding(get: { link != nil }, set: { if !$0 { link = nil } }), presenting: link) { link in
            Button("Connect") {
                link.apply()
                onConnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: { link in
            Text("Home Assistant: \(link.homeHost). The keys and settings from the code replace the ones on this device and on your other devices with the same Apple ID.")
        }
    }
}
