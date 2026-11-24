import Foundation

/// Sara's own settings on this device that she may change when asked. Secrets and connections are not among them.
@MainActor enum AppSettings {
    static let tools = try! JSONSerialization.jsonObject(
        with: Data(contentsOf: Bundle.main.url(forResource: "SettingsTools", withExtension: "json")!)) as! [[String: Any]]

    /// Called after Sara changes how she listens or speaks, so the app restarts listening with the new values.
    static var onVoiceChange: (() -> Void)?

    private static let voiceKeys: Set = ["wakeEnabled", "wakeWord", "speakerEntity"]

    /// nil: not this tool. Applies the changes and returns every setting's value, or the first error.
    static func run(_ name: String, _ args: [String: Any]) async -> String? {
        guard name == "app_settings" else { return nil }
        var voiceChanged = false
        defer { if voiceChanged { onVoiceChange?() } }
        for change in args["changes"] as? [[String: Any]] ?? [] {
            let setting = change["setting"] as? String ?? ""
            let value = (change["value"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let result = await apply(setting, value)
            guard let key = result.key else { return "error: \(result.error ?? setting)" }
            voiceChanged = voiceChanged || voiceKeys.contains(key)
        }
        return current()
    }

    /// The UserDefaults key that changed, or an error.
    private static func apply(_ setting: String, _ value: String) async -> (key: String?, error: String?) {
        let defaults = UserDefaults.standard
        func number(_ key: String, _ range: ClosedRange<Int>) -> (String?, String?) {
            guard let n = Int(value), range.contains(n) else { return (nil, "\(setting) takes a whole number from \(range.lowerBound) to \(range.upperBound)") }
            // These two are stored as Double by the settings screen.
            if key == "followUpSeconds" || key == "window" { defaults.set(Double(n), forKey: key) } else { defaults.set(n, forKey: key) }
            return (key, nil)
        }
        func flag(_ key: String) -> (String?, String?) {
            guard let on = Bool(value.lowercased()) else { return (nil, "\(setting) takes true or false") }
            defaults.set(on, forKey: key)
            return (key, nil)
        }
        switch setting {
        case "wake_word_listening": return flag("wakeEnabled")
        case "wake_word":
            defaults.set(value, forKey: "wakeWord")
            return ("wakeWord", nil)
        case "follow_up_seconds": return number("followUpSeconds", 0...60)
        case "conversation_seconds": return number("window", 30...600)
        case "night_mode": return flag("nightEnabled")
        case "night_start_hour": return number("nightStart", 0...23)
        case "night_end_hour": return number("nightEnd", 0...23)
        case "speaker":
            guard !value.isEmpty else { defaults.set("", forKey: "speakerEntity"); return ("speakerEntity", nil) }
            guard let states = try? await HomeAssistant.saved?.states() else { return (nil, "Home Assistant is unreachable") }
            let players = states.filter { id, state in
                PanelItem.domain(id) == "media_player"
                    && state.attributes["friendly_name"]?.string?.caseInsensitiveCompare(value) == .orderedSame
            }
            guard players.count == 1, let id = players.first?.key else { return (nil, "no single media player named \(value)") }
            defaults.set(id, forKey: "speakerEntity")
            return ("speakerEntity", nil)
        case "room":
            if !value.isEmpty {
                let url = defaults.string(forKey: "haURL") ?? ""
                let areas: [HAArea] = (try? await HomeAssistantSocket(baseURL: url, token: Keychain.get("haToken")).call("config/area_registry/list")) ?? []
                guard let area = areas.map(\.name).first(where: { $0.caseInsensitiveCompare(value) == .orderedSame })
                else { return (nil, "no room named \(value)") }
                defaults.set(area, forKey: "deviceRoom")
            } else {
                defaults.set("", forKey: "deviceRoom")
            }
            return ("deviceRoom", nil)
        default: return (nil, "unknown setting \(setting)")
        }
    }

    private static func current() -> String {
        let d = UserDefaults.standard
        func text(_ key: String) -> String { d.string(forKey: key) ?? "" }
        let speaker = text("speakerEntity")
        return """
        wake_word_listening: \(d.object(forKey: "wakeEnabled") as? Bool ?? true)
        wake_word: \(text("wakeWord").isEmpty ? "(default)" : text("wakeWord"))
        follow_up_seconds: \(Int(d.object(forKey: "followUpSeconds") as? Double ?? 20))
        conversation_seconds: \(Int(d.object(forKey: "window") as? Double ?? 150))
        night_mode: \(d.object(forKey: "nightEnabled") as? Bool ?? PowerSaver.isWallPanel)
        night_start_hour: \(d.object(forKey: "nightStart") as? Int ?? 23)
        night_end_hour: \(d.object(forKey: "nightEnd") as? Int ?? 10)
        speaker: \(speaker.isEmpty ? "(this device)" : speaker)
        room: \(text("deviceRoom").isEmpty ? "(none)" : text("deviceRoom"))
        """
    }
}
