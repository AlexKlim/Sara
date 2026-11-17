import Foundation

enum CloudSettings {
    static let homeWideKeys = ["haURL", "model", "houseNotes"]
    private static var store: NSUbiquitousKeyValueStore { .default }

    static func start() {
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: store, queue: .main) { _ in pull() }
        store.synchronize()
        pull()
        // ponytail: right after launch iCloud may not have downloaded yet, so a device with stale values can still
        // seed them. Fine for the few devices of one home; compare modification dates if it ever bites.
        for key in homeWideKeys where store.string(forKey: key) == nil && !(UserDefaults.standard.string(forKey: key) ?? "").isEmpty {
            push(key)
        }
    }

    static func push(_ key: String) {
        store.set(UserDefaults.standard.string(forKey: key) ?? "", forKey: key)
    }

    private static func pull() {
        for key in homeWideKeys {
            guard let value = store.string(forKey: key) else { continue }
            if value.isEmpty { UserDefaults.standard.removeObject(forKey: key) } else { UserDefaults.standard.set(value, forKey: key) }
        }
    }
}
