import Foundation

struct SetupLink: Equatable {
    static let scheme = "sara-home"

    var values: [String: String]

    static func current() -> SetupLink {
        var values = [String: String]()
        for key in Keychain.keys { values[key] = Keychain.get(key) }
        for key in CloudSettings.homeWideKeys { values[key] = UserDefaults.standard.string(forKey: key) ?? "" }
        return SetupLink(values: values)
    }

    var url: URL? {
        guard let json = try? JSONEncoder().encode(values) else { return nil }
        // base64url: "+" in a query would turn into a space.
        let data = json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return URL(string: "\(Self.scheme)://connect?d=\(data)")
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
    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == "connect",
              var data = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" })?.value
        else { return nil }
        data = data.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        data += String(repeating: "=", count: (4 - data.count % 4) % 4)
        guard let json = Data(base64Encoded: data), let values = try? JSONDecoder().decode([String: String].self, from: json) else { return nil }
        self.values = values
    }
}
