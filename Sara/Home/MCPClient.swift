import Foundation

/// Minimal MCP client for Home Assistant's stateless Streamable HTTP endpoint (/api/mcp).
struct MCPClient {
    let url: URL
    let token: String

    func call(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SaraError("Home Assistant: HTTP \(status)") }

        var body = data
        // The server may answer as an SSE stream. Then the JSON is on the first "data:" line.
        if let text = String(data: data, encoding: .utf8), !text.hasPrefix("{"),
           let line = text.split(separator: "\n").first(where: { $0.hasPrefix("data:") }) {
            body = Data(line.dropFirst(5).utf8)
        }
        guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw SaraError("Home Assistant: bad MCP response")
        }
        if let error = json["error"] as? [String: Any] {
            throw SaraError("Home Assistant: \(error["message"] as? String ?? "MCP error")")
        }
        return json["result"] as? [String: Any] ?? [:]
    }

    /// MCP tools converted to Claude tool definitions.
    func claudeTools() async throws -> [[String: Any]] {
        let tools = try await call("tools/list")["tools"] as? [[String: Any]] ?? []
        return tools.map {
            [
                "name": $0["name"] as? String ?? "",
                "description": $0["description"] as? String ?? "",
                "input_schema": $0["inputSchema"] ?? ["type": "object"],
            ]
        }
    }

    /// Runs a tool and returns its text output and whether it failed.
    func callTool(_ name: String, _ arguments: [String: Any]) async throws -> (String, Bool) {
        let result = try await call("tools/call", ["name": name, "arguments": arguments])
        let text = (result["content"] as? [[String: Any]] ?? [])
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
        return (text, result["isError"] as? Bool ?? false)
    }
}
