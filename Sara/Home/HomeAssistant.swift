import Foundation

/// Home Assistant REST API: entity states and service calls.
struct HomeAssistant {
    let baseURL: String
    let token: String

    func states() async throws -> [String: [String: Any]] {
        let data = try await request("GET", "/api/states")
        let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return Dictionary(list.compactMap { state in (state["entity_id"] as? String).map { ($0, state) } }) { first, _ in first }
    }

    func call(_ domain: String, _ service: String, _ data: [String: Any]) async throws {
        _ = try await request("POST", "/api/services/\(domain)/\(service)", body: data)
    }

    /// Calls a service that returns data, e.g. todo.get_items. Returns its service_response.
    func callForResponse(_ domain: String, _ service: String, _ data: [String: Any]) async throws -> [String: Any] {
        let reply = try await request("POST", "/api/services/\(domain)/\(service)?return_response", body: data)
        return (try JSONSerialization.jsonObject(with: reply) as? [String: Any])?["service_response"] as? [String: Any] ?? [:]
    }

    private func request(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw SaraError("Bad Home Assistant address") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SaraError("Home Assistant: HTTP \(status)") }
        return data
    }
}
