// Self-check for Panel.build. Run from the repo root:
// swiftc -parse-as-library -o /tmp/panelcheck Sara/Models/Panel.swift Sara/Models/PanelBlock.swift Sara/Models/PanelItem.swift Sara/Models/SaraError.swift Sara/Home/HomeAssistantSocket.swift Sara/Home/YandexHome.swift Checks/PanelBuildCheck.swift && /tmp/panelcheck
import Foundation

@main
enum PanelBuildCheck {
    static func main() {
        // Self-check for Panel.build: areas from entities and from devices, hidden/config entities skipped.
        let panel = Panel.build(
            areas: [["area_id": "zal", "name": "Living room"], ["area_id": "bath", "name": "Bathroom"], ["area_id": "empty", "name": "Empty"]],
            devices: [["id": "d1", "area_id": "bath"], ["id": "d2", "area_id": NSNull()]],
            entities: [
                ["ei": "light.main", "ai": "zal"],
                ["ei": "switch.sync", "ai": "zal"],
                ["ei": "light.hidden", "ai": "zal", "hb": true],
                ["ei": "switch.child_lock", "ai": "zal", "ec": 0],
                ["ei": "climate.floor", "di": "d1"],
                ["ei": "light.nowhere", "di": "d2"],
            ["ei": "todo.shopping"],
            ])
        assert(panel.blocks.map(\.title) == ["Living room", "Thermostats", ""], "\(panel.blocks.map(\.title))")
        assert(panel.blocks[2].kind == .list && panel.blocks[2].items.first?.entity == "todo.shopping")
        assert(panel.blocks[0].items.map(\.entity) == ["light.main", "switch.sync"])
        assert(panel.blocks[1].column == 1 && panel.blocks[1].items.first?.name == "Bathroom")
        print("Panel.build OK")

        // Running devices: found by their remaining-time sensor, with the device's other sensors filled in.
        let withRunning = Panel.build(
            areas: [],
            devices: [["id": "p", "name": "Printer"], ["id": "w", "name": "Washer", "name_by_user": "My washer"], ["id": "l", "name": "Lamp"]],
            entities: [
                ["ei": "sensor.kabinet_printer_remaining_time", "di": "p"],
                ["ei": "sensor.kabinet_printer_print_progress", "di": "p"],
                ["ei": "sensor.kabinet_printer_end_time", "di": "p"],
                ["ei": "sensor.kabinet_printer_task_name", "di": "p"],
                ["ei": "sensor.kabinet_printer_print_status", "di": "p"],
                ["ei": "sensor.kabinet_printer_sd_card_status", "di": "p"],
                ["ei": "sensor.tualet_stiralka_remaining_time", "di": "w"],
                ["ei": "sensor.tualet_stiralka_program_phase", "di": "w"],
                ["ei": "binary_sensor.tualet_stiralka_status", "di": "w"],
                ["ei": "light.lamp", "di": "l"],
            ])
        assert(withRunning.blocks.first?.kind == .running && withRunning.blocks.first?.column == 1)
        let printer = withRunning.blocks[0].items[1], washer = withRunning.blocks[0].items[0]
        assert(washer.name == "My washer" && washer.icon == "washer" && washer.active == "binary_sensor.tualet_stiralka_status")
        assert(washer.detail == nil && washer.progress == nil)
        assert(printer.icon == "cube" && printer.active == "sensor.kabinet_printer_print_status")
        assert(printer.progress == "sensor.kabinet_printer_print_progress" && printer.end == "sensor.kabinet_printer_end_time")
        assert(printer.detail == "sensor.kabinet_printer_task_name")
        assert(Panel.runningItem(device: "Lamp", entities: ["light.lamp"]) == nil)
        let dishwasher = Panel.runningItem(device: "Dishwasher", entities: [
            "sensor.electrolux_dishwasher_timetoend", "sensor.electrolux_dishwasher_appliancestate",
            "select.electrolux_dishwasher_userselections_programuid", "sensor.electrolux_dishwasher_cyclephase",
        ])
        assert(dishwasher?.entity == "sensor.electrolux_dishwasher_timetoend" && dishwasher?.icon == "dishwasher")
        assert(dishwasher?.active == "sensor.electrolux_dishwasher_appliancestate")
        assert(dishwasher?.detail == "select.electrolux_dishwasher_userselections_programuid")
        print("Running devices OK")

        // Yandex: user/info in the shape of the docs.
        let info: [String: Any] = [
            "rooms": [["id": "r1", "name": "Kitchen"], ["id": "r2", "name": "Bathroom"]],
            "devices": [
                ["id": "lamp", "name": "Lamp", "room": "r1", "type": "devices.types.light", "capabilities": [
                    ["type": "devices.capabilities.on_off", "state": ["instance": "on", "value": true]],
                    ["type": "devices.capabilities.range", "state": ["instance": "brightness", "value": 50]],
                ]],
                ["id": "floor", "name": "Floor", "room": "r2", "type": "devices.types.thermostat", "capabilities": [
                    ["type": "devices.capabilities.on_off", "state": ["instance": "on", "value": false]],
                    ["type": "devices.capabilities.range", "state": ["instance": "temperature", "value": 28]],
                ], "properties": [["type": "devices.properties.float", "state": ["instance": "temperature", "value": 26.5]]]],
            ],
        ]
        let states = YandexHome.states(from: info)
        assert(states["yandex.lamp"]?["state"] as? String == "on")
        assert(abs(((states["yandex.lamp"]?["attributes"] as? [String: Any])?["brightness"] as? Double ?? 0) - 127.5) < 0.01)
        assert((states["yandex.floor"]?["attributes"] as? [String: Any])?["current_temperature"] as? Double == 26.5)
        let yandexPanel = Panel.build(fromYandex: info)
        assert(yandexPanel.blocks.map(\.title) == ["Kitchen", "Thermostats"], "\(yandexPanel.blocks.map(\.title))")
        assert(yandexPanel.blocks[0].items.map(\.entity) == ["yandex.lamp"])
        assert(yandexPanel.blocks[1].items.first?.name == "Bathroom")
        print("Yandex panel OK")
    }
}
