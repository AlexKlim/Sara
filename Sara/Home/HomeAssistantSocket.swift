import Foundation

/// The Home Assistant WebSocket API: one-shot calls (areas and registries are only available there)
/// and the live subscription to entity states.
struct HomeAssistantSocket {
    let baseURL: String
    let token: String

    /// Sends the commands one by one (e.g. "config/area_registry/list") and returns their results in order.
    func call(_ commands: [String]) async throws -> [Any] {
        let socket = try await connect()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        var results: [Any] = []
        for (index, command) in commands.enumerated() {
            let id = index + 1
            try await send(socket, ["id": id, "type": command])
            var reply = try await receive(socket)
            while reply["id"] as? Int != id { reply = try await receive(socket) }
            guard reply["success"] as? Bool == true, let result = reply["result"] else {
                throw SaraError("Home Assistant: \(command) failed")
            }
            results.append(result)
        }
        return results
    }

    /// Subscribes to all entity states and hands every event to `onEvent` until the connection drops.
    /// Events are compact: "a" added (the first one has every entity), "c" changed ("+" new values, "-" removed
    /// attributes), "r" removed. Each entity is {"s": state, "a": attributes}.
    func subscribeEntities(_ onEvent: @escaping @MainActor ([String: Any]) -> Void) async throws {
        let socket = try await connect()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        try await send(socket, ["id": 1, "type": "subscribe_entities"])

        // A ping now and then keeps the connection from being dropped as idle.
        let pinger = Task {
            var id = 2
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                try? await send(socket, ["id": id, "type": "ping"])
                id += 1
            }
        }
        defer { pinger.cancel() }

        while !Task.isCancelled {
            let message = try await receive(socket)
            switch message["type"] as? String {
            case "event":
                if let event = message["event"] as? [String: Any] { await onEvent(event) }
            case "result" where message["id"] as? Int == 1 && message["success"] as? Bool == false:
                throw SaraError("Home Assistant: subscribe_entities failed")
            default:
                break
            }
        }
    }

    private func connect() async throws -> URLSessionWebSocketTask {
        guard var parts = URLComponents(string: baseURL) else { throw SaraError("Bad Home Assistant address") }
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        parts.path = "/api/websocket"
        guard let url = parts.url else { throw SaraError("Bad Home Assistant address") }

        let socket = URLSession.shared.webSocketTask(with: url)
        socket.maximumMessageSize = 32 * 1024 * 1024 // the entity registry and the first state dump are large
        socket.resume()
        _ = try await receive(socket) // auth_required
        try await send(socket, ["type": "auth", "access_token": token])
        guard try await receive(socket)["type"] as? String == "auth_ok" else {
            socket.cancel(with: .normalClosure, reason: nil)
            throw SaraError("Home Assistant: authentication failed")
        }
        return socket
    }

    private func send(_ socket: URLSessionWebSocketTask, _ message: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: message)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func receive(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
        let data: Data
        switch try await socket.receive() {
        case .string(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        @unknown default: return [:]
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
