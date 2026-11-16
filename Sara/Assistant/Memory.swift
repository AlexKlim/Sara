import Foundation
import SwiftData

/// Long-term memory: facts Sara keeps across conversations.
@MainActor struct Memory {
    let context: ModelContext

    static let tools = try! JSONSerialization.jsonObject(
        with: Data(contentsOf: Bundle.main.url(forResource: "MemoryTools", withExtension: "json")!)) as! [[String: Any]]

    func all() -> [Fact] {
        (try? context.fetch(FetchDescriptor<Fact>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    /// Adds a fact or replaces the one with the same name.
    func save(name: String, type: String, content: String) {
        guard !name.isEmpty, !content.isEmpty else { return }
        if let fact = all().first(where: { $0.name == name }) {
            fact.type = type
            fact.content = content
            fact.updated = .now
        } else {
            context.insert(Fact(name: name, type: type, content: content))
        }
    }

    func delete(name: String) {
        all().filter { $0.name == name }.forEach(context.delete)
    }

    /// All facts as a block for the system prompt.
    func promptBlock() -> String {
        let lines = all().map { "- \($0.name) (\($0.type)): \($0.content)" }
        return "<memory>\n\(lines.isEmpty ? "(empty)" : lines.joined(separator: "\n"))\n</memory>"
    }

    /// Runs memory_save or memory_delete. Returns nil for any other tool.
    func run(_ tool: String, _ args: [String: Any]) -> String? {
        let name = args["name"] as? String ?? ""
        switch tool {
        case "memory_save":
            save(name: name, type: args["type"] as? String ?? "other", content: args["content"] as? String ?? "")
            return "saved"
        case "memory_delete":
            delete(name: name)
            return "deleted"
        default:
            return nil
        }
    }
}
