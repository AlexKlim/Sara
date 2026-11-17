import Foundation

struct SetupLink: Equatable {
    // Not a URL: the system camera would hand a URL to whatever app claims its scheme. Only Sara's own scanner reads this.
    static let prefix = "SARA1:"

    var values: [String: String]

    static func current() -> SetupLink {
        var values = [String: String]()
        for key in Keychain.keys { values[key] = Keychain.get(key) }
        for key in CloudSettings.homeWideKeys { values[key] = UserDefaults.standard.string(forKey: key) ?? "" }
        return SetupLink(values: values)
    }

    var payload: String? {
        guard let json = try? JSONEncoder().encode(values) else { return nil }
        return Self.prefix + json.base64EncodedString()
    }

    var homeHost: String {
        let address = values["haURL"] ?? ""
        return URL(string: address)?.host ?? address
    }

    /// Replaces the whole connection: a key the code does not have is cleared, not kept from another home.
    func apply() {
        for key in Keychain.keys { Keychain.set(key, values[key] ?? "") }
        for key in CloudSettings.homeWideKeys {
            if let value = values[key], !value.isEmpty {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
            CloudSettings.push(key)
        }
    }
}

extension SetupLink {
    init?(payload: String) {
        guard payload.hasPrefix(Self.prefix), let json = Data(base64Encoded: String(payload.dropFirst(Self.prefix.count))),
              let values = try? JSONDecoder().decode([String: String].self, from: json) else { return nil }
        self.values = values
    }
}
