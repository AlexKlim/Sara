import Foundation

/// Home Assistant's live context (the GetLiveContext tool): exposed entities as a YAML list of
/// "- names: A, B" entries with a "domain:" line each. Over MCP it comes wrapped as {"success": …, "result": "…"}.
enum LiveContext {
    /// Names (with aliases) of the entries in these domains.
    static func names(in text: String, domains: Set<String>) -> Set<String> {
        let yaml = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])?["result"] as? String ?? text
        var result = Set<String>()
        for entry in ("\n" + yaml).components(separatedBy: "\n- ").dropFirst() {
            let lines = entry.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            guard lines.contains(where: { $0.hasPrefix("domain: ") && domains.contains(String($0.dropFirst("domain: ".count))) }),
                  let names = lines.first(where: { $0.hasPrefix("names: ") }) else { continue }
            let list = String(names.dropFirst("names: ".count)).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            result.formUnion(list.components(separatedBy: ", "))
        }
        return result
    }
}
