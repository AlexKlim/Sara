import SwiftData
import SwiftUI

@main
struct SaraApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(for: [Turn.self, Fact.self, ListItem.self])
    }
}
