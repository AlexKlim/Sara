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
                if location != loadedFor { forecast = nil }
                if let location, location != loadedFor || Date.now.timeIntervalSince(updated ?? .distantPast) > 20 * 60,
                   let fresh = await Self.fetch(location), Self.location(home) == location {
                    forecast = fresh
                    updated = .now
                    loadedFor = location
                }
                // An old observation is worse than none: Sara would tell it as the weather now.
                if let updated, Date.now.timeIntervalSince(updated) > 3 * 3600 {
                    forecast = nil
                    self.updated = nil
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

    private static func fetch(_ location: HomeLocation) async -> Forecast? {
        guard let url = Forecast.url(latitude: location.latitude, longitude: location.longitude) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw SaraError("Open-Meteo: HTTP \(status)") }
            return try Forecast.decode(data)
        } catch {
            #if DEBUG
            print("[weather] not loaded:", error)
            #endif
            return nil
        }
    }
}
