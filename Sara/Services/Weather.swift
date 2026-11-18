import Foundation

/// The home's forecast from Open-Meteo: free, without a key.
/// The home is the address from Settings, else the home zone of Home Assistant.
@MainActor @Observable final class Weather {
    static let shared = Weather()

    private(set) var forecast: Forecast?
    private(set) var updated: Date?
    private var loadedFor: HomeLocation?
    private var task: Task<Void, Never>?

    func start(home: Home) {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                let location = Self.location(home)
                if let location, location != loadedFor || Date.now.timeIntervalSince(updated ?? .distantPast) > 20 * 60 {
                    await load(location)
                }
                try? await Task.sleep(for: .seconds(location == nil ? 2 : 60))
            }
        }
    }

    private static func location(_ home: Home) -> HomeLocation? {
        if let saved = HomeLocation(stored: UserDefaults.standard.string(forKey: "homeLocation") ?? "") { return saved }
        guard let latitude = home.attribute("zone.home", "latitude") as? Double,
              let longitude = home.attribute("zone.home", "longitude") as? Double else { return nil }
        return HomeLocation(latitude: latitude, longitude: longitude)
    }

    private func load(_ location: HomeLocation) async {
        guard let url = Forecast.url(latitude: location.latitude, longitude: location.longitude) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            forecast = try Forecast.decode(data)
            updated = .now
            loadedFor = location
        } catch {
            #if DEBUG
            print("[weather] not loaded:", error)
            #endif
        }
    }
}
