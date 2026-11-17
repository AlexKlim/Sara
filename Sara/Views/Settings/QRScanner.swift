import SwiftUI
import VisionKit

struct QRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onFail: () -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !scanner.isScanning else { return }
        do { try scanner.startScanning() } catch { Task { onFail() } }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onFail: onFail) }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        let onFail: () -> Void

        init(onScan: @escaping (String) -> Void, onFail: @escaping () -> Void) {
            self.onScan = onScan
            self.onFail = onFail
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let code) in addedItems {
                if let text = code.payloadStringValue { onScan(text) }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onFail()
        }
    }
}
