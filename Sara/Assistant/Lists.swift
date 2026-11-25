import Foundation
import SwiftData

@MainActor enum Lists {
    static let tools = try! JSONSerialization.jsonObject(
        with: Data(contentsOf: Bundle.main.url(forResource: "ListTools", withExtension: "json")!)) as! [[String: Any]]

    /// List names with their open item counts, for Claude. Empty when there are no lists.
    static func summary() async -> String {
        guard let states = try? await HomeAssistant.saved?.states() else { return "" }
        let lines = todos(states).map { "- \($0.name): \($0.open) open" }
        return lines.isEmpty ? "" : "<lists>\n\(lines.joined(separator: "\n"))\n</lists>"
    }

    /// Runs a list tool. Returns nil for any other tool.
    static func run(_ tool: String, _ args: [String: Any]) async -> String? {
        guard tool.hasPrefix("list_") else { return nil }
        guard let api = HomeAssistant.saved else { return "error: Home Assistant is not set up" }
        let asked = (args["list"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let texts = (args["items"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let states = try? await api.states() else { return "error: Home Assistant is unreachable" }
        var list = todos(states).first { $0.name.localizedCaseInsensitiveCompare(asked) == .orderedSame }.map { (id: $0.id, name: $0.name) }
        if list == nil, tool == "list_add" {
            guard !asked.isEmpty else { return "error: no list name" }
            guard let id = await create(asked, api) else { return "error: couldn't create the list in Home Assistant" }
            list = (id, asked)
        }
        guard let list else { return "no list named \(asked)" }
        do {
            let response: [String: [String: [HATodoItem]]] = try await api.callForResponse("todo", "get_items", ["entity_id": list.id])
            let items = response[list.id]?["items"] ?? []
            let matching = { (text: String) in items.filter { $0.summary.localizedCaseInsensitiveContains(text) || text.localizedCaseInsensitiveContains($0.summary) } }

            switch tool {
            case "list_add":
                for text in texts { try await api.call("todo", "add_item", ["entity_id": list.id, "item": text]) }
                Panel.addList(list.name, entity: list.id)
                return "added \(texts.count) to \(list.name)"
            case "list_read":
                let open = items.filter { !$0.done }.map(\.summary)
                let done = items.filter(\.done).map(\.summary)
                return "open: \(open.joined(separator: "; "))\nchecked: \(done.joined(separator: "; "))"
            case "list_check":
                let found = texts.flatMap(matching)
                for item in found { try await api.call("todo", "update_item", ["entity_id": list.id, "item": item.uid, "status": "completed"]) }
                return found.isEmpty ? "nothing matched" : "checked \(found.map(\.summary).joined(separator: ", "))"
            case "list_remove":
                let found = texts.isEmpty ? items : texts.flatMap(matching)
                if !found.isEmpty { try await api.call("todo", "remove_item", ["entity_id": list.id, "item": found.map(\.uid)]) }
                if texts.isEmpty { return "list \(list.name) emptied; it is off the panel until something is added" }
                return found.isEmpty ? "nothing matched" : "removed \(found.map(\.summary).joined(separator: ", "))"
            default:
                return nil
            }
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    static func moveToHomeAssistant(_ context: ModelContext) async {
        guard HomeAssistant.saved != nil,
              let local = try? context.fetch(FetchDescriptor<ListItem>(predicate: #Predicate { $0.closed == nil })),
              !local.isEmpty else { return }
        for (name, items) in Dictionary(grouping: local, by: \.list) {
            let open = items.sorted { $0.created < $1.created }.filter { !$0.done }.map(\.text)
            Panel.removeList(name)
            let result = await run("list_add", ["list": name, "items": open])
            guard result?.hasPrefix("added") == true else {
                Log.write("[lists] \(name) not moved: \(result ?? "-")")
                Panel.addList(name)
                continue
            }
            items.forEach(context.delete)
            Log.write("[lists] \(name) moved to Home Assistant")
        }
    }

    private static func todos(_ states: [String: HAState]) -> [(id: String, name: String, open: String)] {
        states.filter { $0.key.hasPrefix("todo.") }
            .map { (id: $0.key, name: $0.value.attribute("friendly_name") as? String ?? $0.key, open: $0.value.state) }
            .sorted { $0.name < $1.name }
    }

    private static func create(_ name: String, _ api: HomeAssistant) async -> String? {
        do { try await api.call("script", "create_list", ["name": name]) } catch {
            Log.write("[lists] create_list failed: \(error)")
            return nil
        }
        for _ in 0..<20 {
            if let states = try? await api.states(),
               let found = todos(states).first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                return found.id
            }
            try? await Task.sleep(for: .seconds(0.5))
        }
        return nil
    }
}
