import CoreLocation
import SwiftUI

/// The home's address for the weather: typed, or taken from this device's location.
struct HomeLocationView: View {
    @AppStorage("homeLocation") private var stored = ""
    @Environment(\.dismiss) private var dismiss
    @State private var draft = HomeLocation()
    @State private var known: HomeLocation?
    @State private var problem: LocalizedStringKey?
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                TextField("Country", text: $draft.country)
                TextField("City", text: $draft.city)
                TextField("Street", text: $draft.street)
                TextField("House", text: $draft.house)
            } footer: {
                Text(problem ?? "Sara turns the address into coordinates with Apple Maps. The weather service gets only the coordinates.")
            }
            .disabled(busy)
            Section {
                Button("Use this device's location", systemImage: "location") { Task { await fillFromDevice() } }
                    .disabled(busy)
            }
            if !stored.isEmpty {
                Section {
                    Button("Clear", role: .destructive) {
                        stored = ""
                        CloudSettings.push("homeLocation")
                        dismiss()
                    }
                    .disabled(busy)
                }
            }
        }
        .navigationTitle("Home location")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(busy || draft.city.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            if let saved = HomeLocation(stored: stored) {
                draft = saved
                known = saved
            }
        }
    }

    /// Keeps the known coordinates (saved, or found by the device) while the address is unchanged, else looks it up.
    private func save() async {
        busy = true
        defer { busy = false }
        var location = draft
        if draft.address != known?.address {
            guard let located = try? await draft.located() else {
                problem = "Couldn't find this address."
                return
            }
            location = located
        }
        stored = location.stored
        CloudSettings.push("homeLocation")
        dismiss()
    }

    /// Fills the fields from where this device is; they stay editable until Save.
    private func fillFromDevice() async {
        busy = true
        defer { busy = false }
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        let deadline = Date.now + 20
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                guard Date.now < deadline else { break }
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    problem = "Sara has no access to the location. Allow it in the Settings app, or type the address."
                    return
                }
                guard let location = update.location else { continue }
                draft = await HomeLocation.at(location)
                known = draft
                problem = nil
                return
            }
        } catch {}
        problem = "Couldn't get the location."
    }
}
