import Foundation

/// Devices that appeared in Home Assistant and are not on the panel. The panel offers each one until the user
/// adds it or skips it, and Sara says once that it appeared.
@MainActor @Observable final class NewDevices {
    static let shared = NewDevices()
    private(set) var found: [NewDevice] = []
    /// Called once per device, the first time it is found.
    var onFound: ((NewDevice) -> Void)?
    private var checking = false
    private var adding: Set<String> = []
    /// Something changed during a check: check again right after it.
    private var recheck = false
    private let defaults = UserDefaults.standard

    /// Looks for devices that are neither on the panel nor added or skipped before.
    /// The first check takes every device older than a day as known, so only recent ones show.
    func check() async {
        guard !checking else { recheck = true; return }
        checking = true
        repeat {
            recheck = false
            // Home Assistant out of reach: try again in a minute, entities may not change to trigger a check.
            while !(await scan()) { try? await Task.sleep(for: .seconds(60)) }
        } while recheck
        checking = false
    }

    /// False when Home Assistant didn't answer.
    private func scan() async -> Bool {
        guard let socket = Self.socket else { return true }
        guard let devices = try? await Self.devices(socket) else { return false }
        var known = Set(defaults.stringArray(forKey: "knownDevices") ?? [])
        if defaults.stringArray(forKey: "knownDevices") == nil {
            known = Set(devices.filter { $0.created < .now - 86_400 }.map(\.id))
            defaults.set(Array(known), forKey: "knownDevices")
        }
        addRunning(devices)
        let onPanel = Set(Panel.load().blocks.flatMap(\.items).map(\.entity))
        found = devices.filter { !known.contains($0.id) && onPanel.isDisjoint(with: $0.entities + [$0.running?.entity].compactMap { $0 }) }
        var announced = Set(defaults.stringArray(forKey: "announcedDevices") ?? [])
        for device in found where !announced.contains(device.id) {
            announced.insert(device.id)
            onFound?(device)
        }
        defaults.set(Array(announced), forKey: "announcedDevices")
        return true
    }

    private func addRunning(_ devices: [NewDevice]) {
        var panel = Panel.load()
        guard !panel.blocks.isEmpty else { return }
        let saved = defaults.stringArray(forKey: "runningDevices")
        let placed = Set(saved ?? devices.filter { $0.created < .now - 86_400 }.map(\.id))
        let new = devices.filter { $0.running != nil && !placed.contains($0.id) }
        if saved == nil || !new.isEmpty { defaults.set(Array(placed.union(new.map(\.id))), forKey: "runningDevices") }
        guard !new.isEmpty else { return }
        panel.addRunning(new.compactMap(\.running))
        panel.save()
    }

    /// Puts the device on the panel as its own block, with its entities as Home Assistant has them now.
    func add(_ device: NewDevice) async {
        // Reserved until the block is saved: a second tap can't add it twice.
        guard !adding.contains(device.id) else { return }
        adding.insert(device.id)
        defer { adding.remove(device.id) }
        found.removeAll { $0.id == device.id }
        var entities = device.entities
        if let socket = Self.socket, let fresh = try? await Self.devices(socket).first(where: { $0.id == device.id }) {
            entities = fresh.entities
        }
        var panel = Panel.load()
        panel.blocks.append(Panel.block(device: device.name, entities: entities))
        panel.save()
        skip(device)
    }

    func skip(_ device: NewDevice) {
        defaults.set((defaults.stringArray(forKey: "knownDevices") ?? []) + [device.id], forKey: "knownDevices")
        found.removeAll { $0.id == device.id }
    }

    private static var socket: HomeAssistantSocket? {
        let url = UserDefaults.standard.string(forKey: "haURL") ?? ""
        return url.isEmpty ? nil : HomeAssistantSocket(baseURL: url, token: Keychain.get("haToken"))
    }

    /// Enabled devices of integrations (not services like the sun) with something a device block can show.
    private static func devices(_ socket: HomeAssistantSocket) async throws -> [NewDevice] {
        let results = try await socket.call(["config/device_registry/list", "config/entity_registry/list_for_display", "config/area_registry/list"])
        let entities = (results[1] as? [String: Any])?["entities"] as? [[String: Any]] ?? []
        let areas = Dictionary((results[2] as? [[String: Any]] ?? []).compactMap { a in
            (a["area_id"] as? String).map { ($0, a["name"] as? String ?? $0) }
        }) { first, _ in first }
        let domains = PanelBlock.Kind.device.domains
        return (results[0] as? [[String: Any]] ?? []).compactMap { device in
            guard let id = device["id"] as? String, !(device["disabled_by"] is String),
                  device["entry_type"] as? String != "service" else { return nil }
            let own = entities.filter { $0["di"] as? String == id }
            let ids = own.filter { $0["hb"] as? Bool != true && $0["ec"] == nil }
                .compactMap { $0["ei"] as? String }
                .filter { id in domains.contains { id.hasPrefix($0 + ".") } }
            guard !ids.isEmpty else { return nil }
            let name = device["name_by_user"] as? String ?? device["name"] as? String ?? ""
            return NewDevice(
                id: id,
                name: name,
                area: (device["area_id"] as? String).flatMap { areas[$0] },
                entities: ids,
                created: Date(timeIntervalSince1970: device["created_at"] as? Double ?? 0),
                running: Panel.runningItem(device: name, entities: own.compactMap { $0["ei"] as? String }))
        }
    }
}
