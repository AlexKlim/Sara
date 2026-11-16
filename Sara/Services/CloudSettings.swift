import Foundation

enum CloudSettings {
    static let homeWideKeys = ["haURL", "model", "houseNotes"]
    private static var store: NSUbiquitousKeyValueStore { .default }

    static func start() {
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: store, queue: .main) { _ in pull() }
        store.synchronize()
        pull()
        // Only missing keys: a device with stale values must not overwrite newer ones from another device at launch.
        for key in homeWideKeys where store.string(forKey: key) == nil { push(key) }
    }

    static func pushAll() { homeWideKeys.forEach(push) }

    private static func push(_ key: String) {
        guard let value = UserDefaults.standard.string(forKey: key), !value.isEmpty else { return }
        store.set(value, forKey: key)
    }

    private static func pull() {
        for key in homeWideKeys {
            guard let value = store.string(forKey: key), !value.isEmpty else { continue }
            UserDefaults.standard.set(value, forKey: key)
        }
    }
}
