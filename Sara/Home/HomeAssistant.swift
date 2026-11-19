import Foundation

/// Home Assistant REST API: entity states and service calls.
struct HomeAssistant {
    let baseURL: String
    let token: String

    /// The one set up in Settings, if any.
    static var saved: HomeAssistant? {
        let url = UserDefaults.standard.string(forKey: "haURL") ?? ""
        return url.isEmpty ? nil : HomeAssistant(baseURL: url, token: Keychain.get("haToken"))
    }

    func states() async throws -> [String: [String: Any]] {
        let data = try await request("GET", "/api/states", timeout: 10)
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

    func registerMobileApp(_ device: [String: Any]) async throws -> String {
        let reply = try await request("POST", "/api/mobile_app/registrations", body: device)
        guard let id = (try JSONSerialization.jsonObject(with: reply) as? [String: Any])?["webhook_id"] as? String else {
            throw SaraError("Home Assistant: no webhook id")
        }
        return id
    }

    /// Home Assistant answers a webhook it doesn't know with an empty 200, so the reply is returned to check.
    func webhook(_ id: String, _ body: [String: Any]) async throws -> [String: Any] {
        let reply = try await request("POST", "/api/webhook/\(id)", body: body)
        return (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any] ?? [:]
    }

    struct StatusError: LocalizedError {
        let status: Int
        var errorDescription: String? { "Home Assistant: HTTP \(status)" }
    }

    private func request(_ method: String, _ path: String, body: [String: Any]? = nil, timeout: TimeInterval = 60) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw SaraError("Bad Home Assistant address") }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw StatusError(status: status) }
        return data
    }
}
