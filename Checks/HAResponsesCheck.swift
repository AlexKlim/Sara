import Foundation

@main
enum HAResponsesCheck {
    static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
        try! JSONDecoder().decode(type, from: Data(json.utf8))
    }

    static func main() {
        let states = decode([HAState].self, """
            [{"entity_id": "light.main", "state": "on", "attributes": {"friendly_name": "Main", "brightness": 255,
              "supported_color_modes": ["brightness"], "supported_features": 4, "min_temp": 7.5, "restored": true, "icon": null},
              "last_changed": "2026-11-24T22:42:08.123456+00:00", "context": {"id": "x"}}]
            """)
        let light = states[0]
        assert(light.entityID == "light.main" && light.state == "on")
        assert(light.attribute("friendly_name") as? String == "Main")
        assert(light.attribute("brightness") as? Double == 255 && light.attribute("supported_features") as? Int == 4)
        assert(light.attribute("min_temp") as? Double == 7.5)
        assert(light.attribute("supported_color_modes") as? [String] == ["brightness"])
        assert(light.attributes["restored"] == .bool(true) && light.attributes["icon"] == .null)

        let first = decode(HAMessage<HAStatesEvent>.self, """
            {"id": 1, "type": "event", "event": {"a": {"sensor.t": {"s": "21.5", "a": {"unit_of_measurement": "°C"}, "c": "x", "lc": 1.0}}}}
            """)
        assert(first.event?.added["sensor.t"]?.state == "21.5")
        let change = decode(HAMessage<HAStatesEvent>.self, """
            {"id": 1, "type": "event", "event": {"c": {"sensor.t": {"+": {"s": "22", "a": {"x": 1}, "lu": 2.0}, "-": {"a": ["unit_of_measurement"]}}},
             "r": ["light.gone"]}}
            """).event!
        assert(change.changed["sensor.t"]?.state == "22" && change.changed["sensor.t"]?.attributes["x"]?.double == 1)
        assert(change.changed["sensor.t"]?.removedAttributes == ["unit_of_measurement"] && change.removed == ["light.gone"])
        let pong = decode(HAMessage<HAStatesEvent>.self, #"{"id": 7, "type": "pong"}"#)
        assert(pong.event == nil && pong.result == nil)
        
        let areas = decode(HAMessage<[HAArea]>.self, """
            {"id": 1, "type": "result", "success": true, "result": [{"area_id": "zal", "name": "Зал", "aliases": [], "picture": null}]}
            """).result!
        assert(areas == [HAArea(id: "zal", name: "Зал")])
        let devices = decode([HADevice].self, """
            [{"id": "d1", "name": "Washer", "name_by_user": null, "area_id": "tualet", "disabled_by": null, "entry_type": null,
              "created_at": 1700000000.5, "identifiers": [["hon", "x"]]},
             {"id": "d2", "name": "Sun", "name_by_user": "Солнце", "entry_type": "service", "disabled_by": "user"}]
            """)
        assert(devices[0].displayName == "Washer" && devices[0].areaID == "tualet" && devices[0].createdAt == 1700000000.5)
        assert(devices[1].displayName == "Солнце" && devices[1].entryType == "service" && devices[1].disabledBy == "user")
        let entities = decode(HAEntityList.self, """
            {"entity_categories": {"0": "config", "1": "diagnostic"},
             "entities": [{"ei": "sensor.a", "di": "d1", "pl": "hon", "ec": 1}, {"ei": "light.b", "ai": "zal", "hb": true, "en": "B"}]}
            """).entities
        assert(entities[0] == HAEntityEntry(id: "sensor.a", device: "d1", category: 1, platform: "hon"))
        assert(entities[1] == HAEntityEntry(id: "light.b", area: "zal", hidden: true))

        let failed = decode(HAMessageHeader.self, #"{"id": 2, "type": "result", "success": false, "error": {"code": "unauthorized"}}"#)
        assert(failed.id == 2 && failed.success == false)

        let history = decode([[HAHistoryPoint]].self, """
            [[{"entity_id": "sensor.t", "state": "21", "last_changed": "2026-11-24T00:00:00+00:00", "attributes": {}},
              {"state": "22", "last_changed": "2026-11-24T01:00:00.5+00:00"}]]
            """)
        assert(history[0][0].entityID == "sensor.t" && history[0][1].entityID == nil && history[0][1].state == "22")

        let todo = decode(HAServiceResponse<[String: [String: [HATodoItem]]]>.self, """
            {"changed_states": [], "service_response": {"todo.shopping": {"items": [
              {"summary": "Milk", "uid": "1", "status": "needs_action"}, {"summary": "Bread", "uid": "2", "status": "completed", "due": null}]}}}
            """).response
        assert(todo["todo.shopping"]?["items"]?.map(\.done) == [false, true])

        let services = decode([String: [String: HAValue]].self, """
            {"script": {"tv_volume_set": {"name": "Volume", "fields": {"value": {"selector": {"number": {}}}}}}}
            """)
        assert(services["script"]?["tv_volume_set"]?["fields"]?.object?.keys.sorted() == ["value"])
        print("HA responses OK")
    }
}
