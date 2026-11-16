import Foundation
import SwiftData

/// Lists kept in the app: to-do, shopping, packing. Sara manages them by voice; the panel shows them.
@MainActor struct Lists {
    let context: ModelContext

    static let tools = try! JSONSerialization.jsonObject(
        with: Data(contentsOf: Bundle.main.url(forResource: "ListTools", withExtension: "json")!)) as! [[String: Any]]

    func all() -> [ListItem] {
        (try? context.fetch(FetchDescriptor<ListItem>(sortBy: [SortDescriptor(\.created)]))) ?? []
    }

    /// List names with their open item counts, for Claude. Empty when there are no lists.
    func summary() -> String {
        let byList = Dictionary(grouping: all(), by: \.list)
        let names = Set(byList.keys).union(Panel.load().listNames).sorted()
        guard !names.isEmpty else { return "" }
        let lines = names.map { name in
            let items = byList[name] ?? []
            return items.first?.closed == nil ? "- \(name): \(items.filter { !$0.done }.count) open" : "- \(name): closed"
        }
        return "<lists>\n\(lines.joined(separator: "\n"))\n</lists>"
    }

    /// Runs a list tool. Returns nil for any other tool.
    func run(_ tool: String, _ args: [String: Any]) -> String? {
        guard tool.hasPrefix("list_") else { return nil }
        let asked = (args["list"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let texts = (args["items"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // "weekend to-dos" finds "Weekend to-dos". A list without items still exists as a panel block.
        let existing = (all().map(\.list) + Panel.load().listNames).first { $0.localizedCaseInsensitiveCompare(asked) == .orderedSame }
        let name = existing ?? asked
        let items = all().filter { $0.list == name }
        let matching = { (text: String) in items.filter { $0.text.localizedCaseInsensitiveContains(text) || text.localizedCaseInsensitiveContains($0.text) } }

        switch tool {
        case "list_add":
            guard !name.isEmpty else { return "error: no list name" }
            // Adding to a closed list opens it again.
            items.forEach { $0.closed = nil }
            texts.forEach { context.insert(ListItem(list: name, text: $0)) }
            Panel.addList(name)
            return "added \(texts.count) to \(name)"
        case "list_read":
            guard existing != nil else { return "no list named \(asked)" }
            let open = items.filter { !$0.done }.map(\.text)
            let done = items.filter(\.done).map(\.text)
            return "open: \(open.joined(separator: "; "))\nchecked: \(done.joined(separator: "; "))"
        case "list_check":
            let found = texts.flatMap(matching)
            found.forEach { $0.done = true }
            return found.isEmpty ? "nothing matched" : "checked \(found.map(\.text).joined(separator: ", "))"
        case "list_remove":
            if texts.isEmpty {
                items.forEach(context.delete)
                Panel.removeList(name)
                return "list \(name) removed"
            }
            let found = texts.flatMap(matching)
            found.forEach(context.delete)
            return found.isEmpty ? "nothing matched" : "removed \(found.map(\.text).joined(separator: ", "))"
        default:
            return nil
        }
    }
}
