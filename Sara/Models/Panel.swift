import Foundation

/// What the main screen shows: a list of blocks. Stored as JSON in the app settings.
struct Panel: Codable, Equatable {
    var blocks: [PanelBlock] = []

    static func load() -> Panel {
        decoded(UserDefaults.standard.data(forKey: "panel"))
    }

    /// The saved panel, else the bundled personal layout, else empty.
    static func decoded(_ data: Data?) -> Panel {
        data.flatMap { try? JSONDecoder().decode(Panel.self, from: $0) } ?? bundled ?? Panel()
    }

    var listNames: [String] { blocks.filter { $0.kind == .list }.map(\.title) }

    /// A list Sara created shows up on the panel, in the right column.
    static func addList(_ name: String) {
        var panel = load()
        guard !panel.listNames.contains(name) else { return }
        panel.blocks.append(PanelBlock(kind: .list, title: name, column: 1))
        panel.save()
    }

    static func removeList(_ name: String) {
        var panel = load()
        panel.blocks.removeAll { $0.kind == .list && $0.title == name }
        panel.save()
    }

    /// A personal layout can ship as Resources/Panel.local.json. It is git-ignored.
    static var bundled: Panel? {
        guard let url = Bundle.main.url(forResource: "Panel.local", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Panel.self, from: data)
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "panel")
    }

    /// A first layout from Home Assistant: a room block per area with its lights, switches and fans,
    /// thermostats and to-do lists on the right. The user edits it from there.
    static func build(from socket: HomeAssistantSocket) async throws -> Panel {
        build(try await socket.registry())
    }

    /// A block for one device: setpoints first, then sensors, doors and switches. A sensor named like a setpoint
    /// (number.fridge_temperature and sensor.fridge_temperature) is shown as that setpoint's current value.
    static func block(device name: String, entities: [String]) -> PanelBlock {
        let order = PanelBlock.Kind.device.domains
        let setpoints = Set(entities.filter { $0.hasPrefix("number.") || $0.hasPrefix("input_number.") }.map(PanelItem.objectID))
        let items = entities
            .filter { !($0.hasPrefix("sensor.") && setpoints.contains(PanelItem.objectID($0))) }
            .sorted { (order.firstIndex(of: PanelItem.domain($0)) ?? 0, $0) < (order.firstIndex(of: PanelItem.domain($1)) ?? 0, $1) }
        return PanelBlock(kind: .device, title: name, column: 1, items: items.map { PanelItem(entity: $0) })
    }

    /// A device that reports how long it has left (a printer, a washer) is a running device. Its other sensors,
    /// when it has them, give the progress, the finish time, a detail line and whether it works now.
    static func runningItem(device name: String, entities: [String]) -> PanelItem? {
        let sorted = entities.sorted()
        func find(_ domain: String, _ endings: [String]) -> String? {
            for ending in endings {
                if let id = sorted.first(where: { PanelItem.domain($0) == domain && PanelItem.objectID($0).hasSuffix(ending) }) { return id }
            }
            return nil
        }
        guard let remaining = find("sensor", ["remaining_time", "time_remaining", "time_left", "timetoend"]) else { return nil }
        // Entity ids are Latin (transliterated from other languages), so they tell what kind of device it is.
        let kinds = [("print", "cube"), ("dish", "dishwasher"), ("posud", "dishwasher"), ("wash", "washer"), ("stiral", "washer"),
                     ("dry", "dryer"), ("sushil", "dryer")]
        return PanelItem(
            entity: remaining, name: name.isEmpty ? nil : name,
            icon: kinds.first { remaining.contains($0.0) }?.1,
            active: find("binary_sensor", ["_running", "_status"]) ?? find("sensor", ["print_status", "machine_state", "run_state", "operation_state", "appliancestate"]),
            progress: find("sensor", ["print_progress", "_progress"]),
            end: find("sensor", ["end_time", "finish_time", "completion_time"]),
            detail: find("sensor", ["task_name", "current_program"]) ?? find("select", ["programuid"]))
    }

    /// A first layout from Yandex Smart Home: a room block per room with its switchable devices, thermostats on the right.
    static func build(fromYandex info: [String: Any]) -> Panel {
        let devices = info["devices"] as? [[String: Any]] ?? []
        var blocks: [PanelBlock] = []
        var thermostats: [PanelItem] = []
        let rooms = (info["rooms"] as? [[String: Any]] ?? [])
            .sorted { ($0["name"] as? String ?? "").localizedStandardCompare($1["name"] as? String ?? "") == .orderedAscending }
        for room in rooms {
            let inRoom = devices.filter { $0["room"] as? String == room["id"] as? String }
            let switchable = inRoom.filter { device in
                (device["capabilities"] as? [[String: Any]] ?? []).contains { $0["type"] as? String == "devices.capabilities.on_off" }
                    && device["type"] as? String != "devices.types.thermostat"
            }
            if !switchable.isEmpty {
                blocks.append(PanelBlock(kind: .room, title: room["name"] as? String ?? "",
                                         items: switchable.compactMap { ($0["id"] as? String).map { PanelItem(entity: "yandex." + $0) } }))
            }
            thermostats += inRoom.filter { ($0["type"] as? String ?? "").hasPrefix("devices.types.thermostat") }
                .compactMap { ($0["id"] as? String).map { PanelItem(entity: "yandex." + $0, name: room["name"] as? String) } }
        }
        if !thermostats.isEmpty {
            blocks.append(PanelBlock(kind: .climate, title: String(localized: "Thermostats"), column: 1, items: thermostats))
        }
        return Panel(blocks: blocks)
    }

    static func build(_ registry: HARegistry) -> Panel {
        let deviceArea = Dictionary(registry.devices.map { ($0.id, $0.areaID) }) { a, _ in a }
        var byArea: [String: [String]] = [:]
        for entity in registry.entities where entity.hidden != true && entity.category == nil {
            if let area = entity.area ?? entity.device.flatMap({ deviceArea[$0] ?? nil }) { byArea[area, default: []].append(entity.id) }
        }

        let named = registry.areas.map { ($0.id, $0.name) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
        var blocks: [PanelBlock] = []
        var thermostats: [PanelItem] = []
        // To-do lists usually have no area: take them all.
        var lists = registry.entities.map(\.id).filter { id in id.hasPrefix("todo.") && !byArea.values.contains { $0.contains(id) } }
        for (area, name) in named {
            let ids = (byArea[area] ?? []).sorted()
            let tiles = ids.filter { $0.hasPrefix("light.") || $0.hasPrefix("switch.") || $0.hasPrefix("fan.") }
            lists += ids.filter { $0.hasPrefix("todo.") }
            if !tiles.isEmpty {
                blocks.append(PanelBlock(kind: .room, title: name, items: tiles.map { PanelItem(entity: $0) }))
            }
            thermostats += ids.filter { $0.hasPrefix("climate.") }.map { PanelItem(entity: $0, name: name) }
        }
        if !thermostats.isEmpty {
            blocks.append(PanelBlock(kind: .climate, title: String(localized: "Thermostats"), column: 1, items: thermostats))
        }
        blocks += lists.map { PanelBlock(kind: .list, title: "", column: 1, items: [PanelItem(entity: $0)]) }

        // Printers, washers and the like, at the top of the right column. They show only while they work.
        let deviceNames = Dictionary(registry.devices.map { ($0.id, $0.displayName) }) { a, _ in a }
        var byDevice: [String: [String]] = [:]
        for entity in registry.entities {
            if let device = entity.device { byDevice[device, default: []].append(entity.id) }
        }
        let running = byDevice
            .map { (name: deviceNames[$0.key] ?? "", entities: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .compactMap { runningItem(device: $0.name, entities: $0.entities) }
        var panel = Panel(blocks: blocks)
        panel.addRunning(running)
        return panel
    }

    mutating func addRunning(_ items: [PanelItem]) {
        let shown = Set(blocks.filter { $0.kind == .running }.flatMap(\.items).map(\.entity))
        let new = items.filter { !shown.contains($0.entity) }
        guard !new.isEmpty else { return }
        if let index = blocks.firstIndex(where: { $0.kind == .running }) {
            blocks[index].items += new
        } else {
            blocks.insert(PanelBlock(kind: .running, title: String(localized: "Running now"), column: 1, items: new), at: 0)
        }
    }
}
