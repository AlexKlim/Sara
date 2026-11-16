import CoreImage.CIFilterBuiltins
import SwiftUI

struct ShareConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let image = SetupLink.current().payload.flatMap(Self.qr)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let image {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 360)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    Text("On the other iPhone or iPad, open Sara: Settings, Sara, Scan connection.")
                        .multilineTextAlignment(.center)
                    Text("The code holds your keys. It closes in a minute.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Too much for a QR code. Shorten the house notes.")
                }
            }
            .padding(24)
            .navigationTitle("Share connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .task {
            try? await Task.sleep(for: .seconds(60))
            dismiss()
        }
        .onChange(of: scenePhase) { if scenePhase != .active { dismiss() } }
    }

    private static func qr(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
