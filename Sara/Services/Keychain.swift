import Foundation
import Security

enum Keychain {
    static let keys = ["anthropicKey", "haToken", "yandexToken"]

    static func get(_ key: String) -> String {
        var query = item(key, synced: kSecAttrSynchronizableAny)
        query[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Secrets of the home sync through iCloud Keychain. A secret of one device passes `synced: false`.
    static func set(_ key: String, _ value: String, synced: Bool = true) {
        let query = item(key, synced: synced)
        let data = [kSecValueData as String: Data(value.utf8)]
        if SecItemUpdate(query as CFDictionary, data as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(data) { $1 } as CFDictionary, nil)
        }
    }

    static func moveLocalSecretsToICloud() {
        for key in keys {
            var local = item(key, synced: false)
            local[kSecReturnData as String] = true
            var out: AnyObject?
            guard SecItemCopyMatching(local as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { continue }
            // A copy that came from another device is newer than this device's pre-sync one.
            if !exists(key) { set(key, String(decoding: data, as: UTF8.self)) }
            if exists(key) { SecItemDelete(item(key, synced: false) as CFDictionary) }
        }
    }

    private static func exists(_ key: String) -> Bool {
        SecItemCopyMatching(item(key, synced: true) as CFDictionary, nil) == errSecSuccess
    }

    private static func item(_ key: String, synced: Any) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key, kSecAttrSynchronizable as String: synced]
    }
}
