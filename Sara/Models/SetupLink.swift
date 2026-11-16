import Foundation

struct SetupLink: Codable, Equatable {
    static let scheme = "sara-home"

    var anthropicKey = ""
    var haToken = ""
    var yandexToken = ""
    var haURL = ""
    var model = ""
    var houseNotes = ""

    static func current() -> SetupLink {
        let defaults = UserDefaults.standard
        return SetupLink(
            anthropicKey: Keychain.get("anthropicKey"), haToken: Keychain.get("haToken"), yandexToken: Keychain.get("yandexToken"),
            haURL: defaults.string(forKey: "haURL") ?? "", model: defaults.string(forKey: "model") ?? "",
            houseNotes: defaults.string(forKey: "houseNotes") ?? "")
    }

    var url: URL? {
        guard let json = try? JSONEncoder().encode(self) else { return nil }
        // base64url: "+" in a query would turn into a space.
        let data = json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return URL(string: "\(Self.scheme)://connect?d=\(data)")
    }

    var homeHost: String { URL(string: haURL)?.host ?? haURL }

    func apply() {
        for (key, value) in [("anthropicKey", anthropicKey), ("haToken", haToken), ("yandexToken", yandexToken)] where !value.isEmpty {
            Keychain.set(key, value)
        }
        for (key, value) in [("haURL", haURL), ("model", model), ("houseNotes", houseNotes)] where !value.isEmpty {
            UserDefaults.standard.set(value, forKey: key)
        }
    }
}

// In an extension, so the struct keeps its memberwise initializer.
extension SetupLink {
    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == "connect",
              var data = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" })?.value
        else { return nil }
        data = data.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        data += String(repeating: "=", count: (4 - data.count % 4) % 4)
        guard let json = Data(base64Encoded: data), let link = try? JSONDecoder().decode(SetupLink.self, from: json) else { return nil }
        self = link
    }
}
