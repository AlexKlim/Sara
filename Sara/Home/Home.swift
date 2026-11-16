import Foundation

/// Live state of the home for the panel: a live Home Assistant subscription (polling while it is down),
/// Yandex polled, and taps and sliders.
@MainActor @Observable final class Home {
    /// Home Assistant states, plus Yandex devices as "yandex.<id>" (see YandexHome.states).
    private(set) var states: [String: [String: Any]] = [:]
    private var haStates: [String: [String: Any]] = [:]
    private var yandexStates: [String: [String: Any]] = [:]
    private var polls = 0
    /// Items of Home Assistant to-do lists shown on the panel, by entity id.
    private(set) var todoItems: [String: [[String: Any]]] = [:]
    private var polling: Task<Void, Never>?
    private var subscription: Task<Void, Never>?
    /// The WebSocket subscription is delivering states, so Home Assistant needs no polling.
    private var live = false
    private var connectedURL = ""
    private var platforms: [String: String] = [:]

    private var yandex: YandexHome? {
        let token = Keychain.get("yandexToken")
        return token.isEmpty ? nil : YandexHome(token: token)
    }

    private var api: HomeAssistant? {
        let url = UserDefaults.standard.string(forKey: "haURL") ?? ""
        return url.isEmpty ? nil : HomeAssistant(baseURL: url, token: Keychain.get("haToken"))
    }

    /// Subscribes to Home Assistant states (reconnecting after 5 s when the connection drops) and polls the rest
    /// every few seconds: Yandex, and Home Assistant itself while the subscription is down.
    func start() {
        polling?.cancel()
        subscription?.cancel()
        live = false
        let url = UserDefaults.standard.string(forKey: "haURL") ?? ""
        if url != connectedURL {
            haStates = [:]
            platforms = [:]
            connectedURL = url
        }
        if !url.isEmpty {
            let socket = HomeAssistantSocket(baseURL: url, token: Keychain.get("haToken"))
            subscription = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await socket.subscribeEntities { self?.apply($0) } } catch {
                        #if DEBUG
                        print("[home] subscription dropped:", error)
                        #endif
                    }
                    self?.live = false
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// One event of the subscription: entities added, changed or removed.
    private func apply(_ event: [String: Any]) {
        if !live {
            live = true
            #if DEBUG
            print("[home] live subscription")
            #endif
        }
        for (id, entity) in event["a"] as? [String: [String: Any]] ?? [:] {
            haStates[id] = ["state": entity["s"] as? String ?? "", "attributes": entity["a"] as? [String: Any] ?? [:]]
        }
        for (id, change) in event["c"] as? [String: [String: Any]] ?? [:] {
            var entity = haStates[id] ?? ["state": "", "attributes": [String: Any]()]
            var attributes = entity["attributes"] as? [String: Any] ?? [:]
            if let added = change["+"] as? [String: Any] {
                if let state = added["s"] as? String { entity["state"] = state }
                attributes.merge(added["a"] as? [String: Any] ?? [:]) { _, new in new }
            }
            for key in (change["-"] as? [String: Any])?["a"] as? [String] ?? [] { attributes[key] = nil }
            entity["attributes"] = attributes
            haStates[id] = entity
        }
        for id in event["r"] as? [String] ?? [] { haStates[id] = nil }
        states = haStates.merging(yandexStates) { ha, _ in ha }
    }

    /// Home Assistant by REST unless the subscription is live, Yandex every third time (slower, rate limited).
    func refresh(yandexNow: Bool = false) async {
        if !live, let fresh = try? await api?.states() { haStates = fresh }
        if yandexNow || polls % 3 == 0, let info = try? await yandex?.info() { yandexStates = YandexHome.states(from: info) }
        polls += 1
        states = haStates.merging(yandexStates) { ha, _ in ha }
    }

    // MARK: Reading

    func state(_ id: String?) -> String? { id.flatMap { states[$0]?["state"] as? String } }
    func attribute(_ id: String, _ key: String) -> Any? { (states[id]?["attributes"] as? [String: Any])?[key] }
    func number(_ id: String?) -> Double? { state(id).flatMap(Double.init) }
    func isOn(_ id: String) -> Bool { state(id) == "on" }

    func name(_ item: PanelItem) -> String {
        item.name ?? attribute(item.entity, "friendly_name") as? String ?? item.entity
    }

    /// Minutes left from a remaining-time sensor, using its unit (h, min or s).
    func minutesLeft(_ id: String) -> Double? {
        guard let value = number(id) else { return nil }
        switch attribute(id, "unit_of_measurement") as? String {
        case "h": return value * 60
        case "s": return value / 60
        default: return value
        }
    }

    func date(_ id: String?) -> Date? {
        guard let text = state(id) else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    /// A running device is shown while its `active` sensor says so, or, without one,
    /// while it has time left or is between 0 and 100 percent.
    func isRunning(_ item: PanelItem) -> Bool {
        if let active = item.active { return ["on", "running", "pause", "prepare"].contains(state(active)) }
        if let minutes = minutesLeft(item.entity), minutes > 0 { return true }
        if let progress = number(item.progress), progress > 0, progress < 100 { return true }
        return false
    }

    /// Slider position 0-100.
    func value(_ item: PanelItem) -> Double? {
        if item.entity.hasPrefix("media_player.") { return (attribute(item.entity, "volume_level") as? Double).map { $0 * 100 } }
        if item.entity.hasPrefix("light.") || item.entity.hasPrefix("yandex.") { return isOn(item.entity) ? (attribute(item.entity, "brightness") as? Double ?? 0) / 2.55 : 0 }
        return number(item.entity)
    }

    // MARK: Actions

    func toggle(_ id: String) async {
        let domain = id.components(separatedBy: ".").first ?? ""
        if domain == "yandex" {
            _ = await yandex?.run("yandex_device_action", [
                "device_id": String(id.dropFirst("yandex.".count)),
                "actions": [["capability": "on_off", "instance": "on", "value": !isOn(id)]],
            ])
            await refresh(yandexNow: true)
            return
        }
        if domain == "scene" || domain == "script" {
            try? await api?.call(domain, "turn_on", ["entity_id": id])
        } else {
            try? await api?.call("homeassistant", "toggle", ["entity_id": id])
        }
        await refresh()
    }

    func setValue(_ item: PanelItem, _ value: Double) async {
        if let script = item.script {
            let name = script.replacingOccurrences(of: "script.", with: "")
            try? await api?.call("script", name, [item.field ?? "value": Int(value.rounded())])
        } else if item.entity.hasPrefix("media_player.") {
            try? await api?.call("media_player", "volume_set", ["entity_id": item.entity, "volume_level": value / 100])
        } else if item.entity.hasPrefix("light.") {
            try? await api?.call("light", "turn_on", ["entity_id": item.entity, "brightness_pct": Int(value.rounded())])
        } else if item.entity.hasPrefix("yandex.") {
            _ = await yandex?.run("yandex_device_action", [
                "device_id": String(item.entity.dropFirst("yandex.".count)),
                "actions": [["capability": "range", "instance": "brightness", "value": Int(value.rounded())]],
            ])
        }
        await refresh()
    }

    /// Stops a Home Assistant speaker (a Yandex Station in local mode stops reading).
    func stop(_ speaker: String) async {
        try? await api?.call("media_player", "media_stop", ["entity_id": speaker])
    }

    func loadTodo(_ id: String) async {
        guard let response = try? await api?.callForResponse("todo", "get_items", ["entity_id": id]) else { return }
        todoItems[id] = (response[id] as? [String: Any])?["items"] as? [[String: Any]] ?? []
    }

    func setTodo(_ id: String, item uid: String, done: Bool) async {
        try? await api?.call("todo", "update_item", ["entity_id": id, "item": uid, "status": done ? "completed" : "needs_action"])
        await loadTodo(id)
    }

    func say(_ text: String, on speaker: String) async throws {
        guard let api else { throw SaraError("No Home Assistant address") }
        // A Yandex Station speaks text itself, in Alice's voice. Other players need a text-to-speech engine in HA.
        if await platform(of: speaker) == "yandex_station" {
            try await api.call("media_player", "play_media", ["entity_id": speaker, "media_content_id": text, "media_content_type": "text"])
            return
        }
        guard let engine = states.keys.filter({ $0.hasPrefix("tts.") }).sorted().first else {
            throw SaraError(String(localized: "Home Assistant has no text-to-speech engine"))
        }
        try await api.call("tts", "speak", ["entity_id": engine, "media_player_entity_id": speaker, "message": text,
                                           "language": Locale.current.language.languageCode?.identifier ?? "en"])
    }

    private func platform(of entity: String) async -> String? {
        if let known = platforms[entity] { return known }
        let socket = HomeAssistantSocket(baseURL: connectedURL, token: Keychain.get("haToken"))
        let entities = (try? await socket.call(["config/entity_registry/list_for_display"]).first as? [String: Any])?["entities"] as? [[String: Any]] ?? []
        for entity in entities {
            if let id = entity["ei"] as? String, let platform = entity["pl"] as? String { platforms[id] = platform }
        }
        return platforms[entity]
    }
}
