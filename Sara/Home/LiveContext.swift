import Foundation

/// Home Assistant's live context (the GetLiveContext tool): exposed entities as a YAML list of
/// "- names: A, B" entries with a "domain:" line each. Over MCP it comes wrapped as {"success": …, "result": "…"}.
enum LiveContext {
    /// The name is one of the names (or aliases) of an entry in these domains. Names are joined with ", " and may
    /// contain it themselves, so the name must fill the whole list or sit between its separators.
    static func exposes(_ name: String, in text: String, domains: Set<String>) -> Bool {
        let yaml = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])?["result"] as? String ?? text
        return ("\n" + yaml).components(separatedBy: "\n- ").dropFirst().contains { entry in
            let lines = entry.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            guard lines.contains(where: { $0.hasPrefix("domain: ") && domains.contains(String($0.dropFirst("domain: ".count))) }),
                  let line = lines.first(where: { $0.hasPrefix("names: ") }) else { return false }
            let list = ", " + scalar(String(line.dropFirst("names: ".count))) + ", "
            return list.contains(", " + name + ", ")
        }
    }

    /// A YAML scalar on one line: 'single' ('' is a quote) or "double" (\" is a quote), else plain as it is.
    private static func scalar(_ value: String) -> String {
        guard value.count >= 2, let quote = value.first, quote == "'" || quote == "\"", value.last == quote else { return value }
        let inner = String(value.dropFirst().dropLast())
        return quote == "'" ? inner.replacingOccurrences(of: "''", with: "'") : inner.replacingOccurrences(of: "\\\"", with: "\"")
    }
}
