import Foundation

/// The Home Assistant WebSocket API: one-shot calls (areas and registries are only available there)
/// and the live subscription to entity states.
struct HomeAssistantSocket {
    let baseURL: String
    let token: String

    func call<Result: Decodable>(_ command: String) async throws -> Result {
        try result(Result.self, of: try await replies([command])[0], command)
    }


    func registry() async throws -> HARegistry {
        let commands = ["config/area_registry/list", "config/device_registry/list", "config/entity_registry/list_for_display"]
        let replies = try await replies(commands)
        return HARegistry(
            areas: try result([HAArea].self, of: replies[0], commands[0]),
            devices: try result([HADevice].self, of: replies[1], commands[1]),
            entities: try result(HAEntityList.self, of: replies[2], commands[2]).entities)
    }

    /// Subscribes to all entity states and hands every event to `onEvent` until the connection drops.
    func subscribeEntities(_ onEvent: @escaping @MainActor (HAStatesEvent) -> Void) async throws {
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
            let message = try JSONDecoder().decode(HAMessage<HAStatesEvent>.self, from: try await receive(socket))
            switch message.type {
            case "event":
                if let event = message.event { await onEvent(event) }
            case "result" where message.id == 1 && message.success == false:
                throw SaraError("Home Assistant: subscribe_entities failed")
            default:
                break
            }
        }
    }

    private func replies(_ commands: [String]) async throws -> [Data] {
        let socket = try await connect()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        var replies: [Data] = []
        for (index, command) in commands.enumerated() {
            let id = index + 1
            try await send(socket, ["id": id, "type": command])
            var reply = try await receive(socket)
            var header = try JSONDecoder().decode(HAMessageHeader.self, from: reply)
            while header.id != id {
                reply = try await receive(socket)
                header = try JSONDecoder().decode(HAMessageHeader.self, from: reply)
            }
            guard header.success == true else { throw SaraError("Home Assistant: \(command) failed") }
            replies.append(reply)
        }
        return replies
    }

    private func result<Result: Decodable>(_ type: Result.Type, of reply: Data, _ command: String) throws -> Result {
        guard let result = try JSONDecoder().decode(HAMessage<Result>.self, from: reply).result else {
            throw SaraError("Home Assistant: \(command) returned nothing")
        }
        return result
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
        guard try JSONDecoder().decode(HAMessageHeader.self, from: try await receive(socket)).type == "auth_ok" else {
            socket.cancel(with: .normalClosure, reason: nil)
            throw SaraError("Home Assistant: authentication failed")
        }
        return socket
    }

    private func send(_ socket: URLSessionWebSocketTask, _ message: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: message)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func receive(_ socket: URLSessionWebSocketTask) async throws -> Data {
        switch try await socket.receive() {
        case .string(let text): Data(text.utf8)
        case .data(let bytes): bytes
        @unknown default: Data()
        }
    }
}
