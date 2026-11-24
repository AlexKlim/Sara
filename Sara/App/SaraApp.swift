import SwiftData
import SwiftUI

@main
struct SaraApp: App {
    init() {
        let panel = UIDevice.current.userInterfaceIdiom == .pad && !ProcessInfo.processInfo.isiOSAppOnMac
        UserDefaults.standard.register(defaults: ["wakeEnabled": panel])
    }

    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(for: [Turn.self, Fact.self, ListItem.self])
    }
}
