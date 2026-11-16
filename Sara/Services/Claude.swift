import Foundation

/// Claude Messages API over raw HTTP (there is no official Swift SDK).
struct Claude {
    static let defaultModel = "claude-opus-5-5"
    let apiKey: String
    let model: String

    /// Web search runs on Anthropic's side. The basic version on purpose: the newer one (web_search_20260209)
    /// filters results by running code in several rounds, which took ~19 s for "what's the news" by voice.
    var webSearchTool: [String: Any] {
        ["type": "web_search_20250305", "name": "web_search", "max_uses": 3]
    }

    /// One request, whole response at once. With `schema`, the reply is JSON matching it (structured output).
    func send(system: String, tools: [[String: Any]] = [], messages: [[String: Any]], schema: [String: Any]? = nil) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request(system: system, tools: tools, messages: messages, schema: schema, stream: false))
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Self.error(json) }
        return json
    }

    /// One streamed request. Every server event goes to `onEvent` as it arrives (to show text and speak early).
    /// Returns the assembled message in the same shape as `send`.
    // Client tools keep the default buffered input streaming: their inputs are tiny, and the API validates them.
    func stream(system: String, tools: [[String: Any]], messages: [[String: Any]],
                onEvent: @MainActor ([String: Any]) -> Void) async throws -> [String: Any] {
        let (bytes, response) = try await URLSession.shared.bytes(for: request(system: system, tools: tools, messages: messages, schema: nil, stream: true))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw Self.error((try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
        }

        var message: [String: Any] = [:]
        var blocks: [[String: Any]] = []
        var inputJSON: [Int: String] = [:]
        for try await line in bytes.lines {
            guard line.hasPrefix("data:"),
                  let event = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any]
            else { continue }
            await onEvent(event)
            let i = event["index"] as? Int ?? 0
            switch event["type"] as? String {
            case "message_start":
                message = event["message"] as? [String: Any] ?? [:]
            case "content_block_start":
                let block = event["content_block"] as? [String: Any] ?? [:]
                if i < blocks.count { blocks[i] = block } else { blocks.append(block) }
            case "content_block_delta":
                let delta = event["delta"] as? [String: Any] ?? [:]
                switch delta["type"] as? String {
                case "text_delta": blocks[i]["text"] = (blocks[i]["text"] as? String ?? "") + (delta["text"] as? String ?? "")
                case "thinking_delta": blocks[i]["thinking"] = (blocks[i]["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
                case "signature_delta": blocks[i]["signature"] = delta["signature"]
                case "input_json_delta": inputJSON[i, default: ""] += delta["partial_json"] as? String ?? ""
                case "citations_delta": blocks[i]["citations"] = (blocks[i]["citations"] as? [Any] ?? []) + [delta["citation"] ?? [:]]
                default: break
                }
            case "content_block_stop":
                if let raw = inputJSON[i], let input = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) {
                    blocks[i]["input"] = input
                }
            case "message_delta":
                (event["delta"] as? [String: Any] ?? [:]).forEach { message[$0.key] = $0.value }
            case "error":
                throw Self.error(event)
            default:
                break
            }
        }
        message["content"] = blocks
        return message
    }

    /// All text blocks of a response joined. Search citations split text mid-sentence, so no separator.
    static func text(of response: [String: Any]) -> String {
        (response["content"] as? [[String: Any]] ?? [])
            .compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined()
    }

    private func request(system: String, tools: [[String: Any]], messages: [[String: Any]], schema: [String: Any]?, stream: Bool) throws -> URLRequest {
        var output: [String: Any] = ["effort": "low"]
        if let schema { output["format"] = ["type": "json_schema", "schema": schema] }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": stream ? 64000 : 16000,
            "system": system,
            "messages": messages,
            "output_config": output,
            "cache_control": ["type": "ephemeral"],
            "stream": stream,
        ]
        if !tools.isEmpty { body["tools"] = tools }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // On a safety refusal the API retries on a fallback model by itself. Haiku has no fallback.
        if !model.contains("haiku") {
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func error(_ json: [String: Any]) -> SaraError {
        SaraError("Claude: \((json["error"] as? [String: Any])?["message"] as? String ?? "HTTP error")")
    }
}
