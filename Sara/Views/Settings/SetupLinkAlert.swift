import SwiftUI

extension View {
    /// Attached to every screen that can be on top, since an alert can't show over a sheet.
    func setupLinkAlert(_ link: Binding<SetupLink?>, onConnect: @escaping () -> Void) -> some View {
        alert("Connect to this home?", isPresented: Binding(get: { link.wrappedValue != nil }, set: { if !$0 { link.wrappedValue = nil } }),
              presenting: link.wrappedValue) { link in
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
