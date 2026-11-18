import Foundation
import SwiftData

/// The assistant: keeps the current chat, runs the Claude tool loop over Home Assistant MCP tools
/// and keeps long-term memory up to date.
@MainActor @Observable final class Sara {
    /// How a phrase ended.
    enum Outcome {
        case answered
        /// Heard without the wake word and not addressed to Sara: no answer, the turn is removed.
        case ignored
        /// The user is done: the conversation is closed.
        case ended
        /// Cancelled because the user said more: the phrase is sent again together with the new one.
        case interrupted
    }

    /// The user may barge in: Sara is thinking but has not acted or answered yet, so the request can be redone.
    var canInterrupt: Bool {
        busy && currentTurn?.actions.isEmpty == true && currentTurn?.reply == nil
    }
    private var currentTurn: Turn?

    var busy = false
    /// What Sara is doing right now, already localized. nil when idle.
    var status: String?
    private var messages: [[String: Any]] = []
    private var tools: [[String: Any]] = []
    private var system = ""
    private var lastExchange = Date.distantPast
    /// The current conversation. The main screen shows only its turns.
    private(set) var chatID = UUID()
    private var pendingClose: Task<Void, Never>?
    /// When the last conversation was closed by the chat window running out.
    private(set) var timedOutAt: Date?
    /// Speaks text aloud while it streams in. nil for typed questions.
    private var speak: ((String) -> Void)?
    /// false for speakers that cut themselves off on every new phrase: they get the whole reply at the end.
    private var speakBySentence = true
    /// Streamed text not spoken yet: it is spoken sentence by sentence.
    private var unspoken = ""
    private var spokeThisTurn = false

    /// Base system prompt. The owner's house notes and the memory are appended to it.
    static let prompt = resource("SystemPrompt", "md")
    static let conversationTools = try! JSONSerialization.jsonObject(with: Data(resource("ConversationTools", "json").utf8)) as! [[String: Any]]
    /// "This device is in the room ...", added when the device's room is set.
    static let roomPrompt = resource("RoomPrompt", "md")
    /// The app paused "{player}" while Sara listens; and the note for a later phrase once that pause is over.
    static let musicPausedNote = resource("MusicPausedNote", "md")
    static let musicResumedNote = resource("MusicResumedNote", "md")
    static let extractionPrompt = resource("ExtractionPrompt", "md")
    static let extractionSchema = try! JSONSerialization.jsonObject(with: Data(resource("ExtractionSchema", "json").utf8)) as! [String: Any]

    private static func resource(_ name: String, _ ext: String) -> String {
        try! String(contentsOf: Bundle.main.url(forResource: name, withExtension: ext)!, encoding: .utf8)
    }

    private var claude: Claude {
        Claude(apiKey: Keychain.get("anthropicKey"), model: UserDefaults.standard.string(forKey: "model") ?? Claude.defaultModel)
    }

    /// Sends one phrase and saves the exchange in `context`. With `speak`, the reply is spoken as it streams in.
    /// Within the chat window the previous exchanges stay in Claude's context.
    /// `withoutWakeWord`: a follow-up that may be meant for someone else; Sara may ignore it.
    /// `note`: what the app knows and Claude can't see, sent with the phrase.
    @discardableResult
    func ask(_ text: String, in context: ModelContext, speak: ((String) -> Void)? = nil, bySentence: Bool = true,
             withoutWakeWord: Bool = false, note: String? = nil) async -> Outcome {
        let defaults = UserDefaults.standard
        let window = defaults.object(forKey: "window") as? Double ?? 150
        let memory = Memory(context: context)
        let clock = ContinuousClock()
        let started = clock.now
        let newChat = messages.isEmpty || Date.now.timeIntervalSince(lastExchange) > window
        if newChat { messages = []; chatID = UUID() }
        let turn = Turn(chatID: chatID, user: text)
        Self.markForExtraction(chatID)
        context.insert(turn)
        currentTurn = turn
        // Where this phrase starts in the history, to drop it if it was not for Sara or was interrupted.
        let start = messages.count
        self.speak = speak
        speakBySentence = bySentence
        unspoken = ""
        spokeThisTurn = false
        busy = true
        status = String(localized: "Thinking...")
        defer {
            busy = false
            status = nil
            lastExchange = .now
            currentTurn = nil
            if !turn.isDeleted { turn.totalSeconds = (clock.now - started) / .seconds(1) }
            scheduleClose(after: window, in: context)
        }

        do {
            // The home comes from Home Assistant (MCP), Yandex Smart Home, or both.
            let mcp = URL(string: (defaults.string(forKey: "haURL") ?? "") + "/api/mcp")
                .flatMap { $0.host == nil ? nil : MCPClient(url: $0, token: Keychain.get("haToken")) }
            let yandexToken = Keychain.get("yandexToken")
            let yandex = yandexToken.isEmpty ? nil : YandexHome(token: yandexToken)
            guard mcp != nil || yandex != nil else {
                throw SaraError(String(localized: "Set up Home Assistant or Yandex Smart Home in Settings"))
            }
            let claude = claude

            if newChat {
                let t = clock.now
                let homeTools = (try await mcp?.claudeTools() ?? []) + (yandex == nil ? [] : YandexHome.tools)
                tools = homeTools + Memory.tools + Lists.tools + Alarms.tools + Self.conversationTools + [claude.webSearchTool]
                turn.haSeconds += (clock.now - t) / .seconds(1)
                let room = defaults.string(forKey: "deviceRoom") ?? ""
                system = [Self.prompt, room.isEmpty ? "" : Self.roomPrompt.replacingOccurrences(of: "{room}", with: room),
                          defaults.string(forKey: "houseNotes") ?? "", memory.promptBlock()].joined(separator: "\n\n")
            }
            // Send the current home state with the phrase, so Sara doesn't spend a Claude round trip on GetLiveContext.
            // The current local time: Claude doesn't know it, and timers, alarms and "tonight" need it.
            var content: [[String: Any]] = [
                ["type": "text", "text": "<now>\(Date.now.formatted(date: .complete, time: .shortened))</now>" + (note.map { "\n\($0)" } ?? "")],
                ["type": "text", "text": text],
            ]
            let lists = Lists(context: context)
            let listSummary = lists.summary()
            if !listSummary.isEmpty { content.insert(["type": "text", "text": listSummary], at: 0) }
            if let forecast = Weather.shared.forecast { content.insert(["type": "text", "text": forecast.summary()], at: 0) }
            if let yandex {
                let t = clock.now
                if let state = try? await yandex.stateText() {
                    content.insert(["type": "text", "text": "<yandex_home>\n\(state)\n</yandex_home>"], at: 0)
                }
                turn.haSeconds += (clock.now - t) / .seconds(1)
            }
            if let mcp, let live = tools.lazy.compactMap({ $0["name"] as? String }).first(where: { $0.hasSuffix("GetLiveContext") }) {
                let t = clock.now
                if let (state, failed) = try? await mcp.callTool(live, [:]), !failed {
                    content.insert(["type": "text", "text": "<home_state>\n\(state)\n</home_state>"], at: 0)
                }
                turn.haSeconds += (clock.now - t) / .seconds(1)
            }
            if withoutWakeWord {
                content.append(["type": "text", "text": "<heard_without_wake_word/>"])
            }
            messages.append(["role": "user", "content": content])

            for _ in 0..<10 {
                status = String(localized: "Thinking...")
                let t = clock.now
                let response = try await claude.stream(system: system, tools: tools, messages: messages) { event in
                    if turn.firstTextSeconds == nil, Self.isText(event) { turn.firstTextSeconds = (clock.now - started) / .seconds(1) }
                    self.handle(event, turn: turn)
                }
                turn.claudeSeconds.append((clock.now - t) / .seconds(1))
                // Append the full content unchanged: thinking blocks must go back as they came.
                let content = response["content"] as? [[String: Any]] ?? []
                messages.append(["role": "assistant", "content": content])

                for search in content where search["type"] as? String == "server_tool_use" && search["name"] as? String == "web_search" {
                    turn.actions.append(Self.describe(search["name"] as? String ?? "", search["input"] as? [String: Any] ?? [:]))
                }
                // A long server-side search can pause the turn. Sending the conversation back lets it continue.
                if response["stop_reason"] as? String == "pause_turn" { continue }
                if response["stop_reason"] as? String == "refusal" {
                    finish(turn, String(localized: "I can't help with that."))
                    return .answered
                }
                let calls = content.filter { $0["type"] as? String == "tool_use" }
                if calls.isEmpty {
                    finish(turn, Claude.text(of: response))
                    return .answered
                }
                let names = calls.compactMap { $0["name"] as? String }
                if names.contains("not_for_me") {
                    // Not for Sara: drop it from Claude's context, the screen and the history, as if never heard.
                    // Cutting the tail keeps earlier messages (and their thinking blocks) unchanged.
                    messages.removeSubrange(start...)
                    context.delete(turn)
                    return .ignored
                }
                if names.contains("end_conversation") {
                    let farewell = calls.first { $0["name"] as? String == "end_conversation" }
                        .flatMap { ($0["input"] as? [String: Any])?["farewell"] as? String } ?? ""
                    finish(turn, farewell)
                    startNewChat(in: context)
                    return .ended
                }

                var results: [[String: Any]] = []
                for call in calls {
                    let name = call["name"] as? String ?? ""
                    let args = call["input"] as? [String: Any] ?? [:]
                    let short = name.components(separatedBy: "__").last ?? name
                    status = String(localized: "Running \(short)")
                    turn.actions.append(Self.describe(short, args))
                    var output: String, failed: Bool
                    if let saved = memory.run(name, args) {
                        (output, failed) = (saved, false)
                    } else if let result = lists.run(name, args) {
                        (output, failed) = (result, result.hasPrefix("error"))
                    } else if let alarm = await Alarms.shared.run(name, args) {
                        (output, failed) = (alarm, alarm.hasPrefix("error"))
                    } else if let result = await yandex?.run(name, args) {
                        (output, failed) = (result, result.hasPrefix("error"))
                    } else if let mcp {
                        let t = clock.now
                        do { (output, failed) = try await mcp.callTool(name, args) }
                        catch { (output, failed) = (error.localizedDescription, true) }
                        turn.haSeconds += (clock.now - t) / .seconds(1)
                    } else {
                        (output, failed) = ("unknown tool", true)
                    }
                    results.append([
                        "type": "tool_result", "tool_use_id": call["id"] as? String ?? "",
                        "content": output.isEmpty ? "ok" : output, "is_error": failed,
                    ])
                }
                messages.append(["role": "user", "content": results])
            }
            throw SaraError(String(localized: "Too many steps, try something simpler"))
        } catch {
            if Task.isCancelled {
                // Barge-in: forget this attempt. The phrase comes back together with what the user added.
                if start < messages.count { messages.removeSubrange(start...) }
                context.delete(turn)
                return .interrupted
            }
            messages = []
            finish(turn, error.localizedDescription)
            return .answered
        }
    }

    /// Shows streamed text right away, speaks it sentence by sentence, and tells when Sara searches the web.
    private func handle(_ event: [String: Any], turn: Turn) {
        if Self.isText(event), let text = (event["delta"] as? [String: Any])?["text"] as? String {
            turn.reply = (turn.reply ?? "") + text
            unspoken += text
            // Speak every finished sentence. "22.8" is not a sentence end: a space or new line must follow.
            while speakBySentence, let end = unspoken.range(of: #"[.!?…]+\s|\n"#, options: .regularExpression) {
                say(String(unspoken[..<end.upperBound]))
                unspoken.removeSubrange(..<end.upperBound)
            }
        } else if event["type"] as? String == "content_block_start",
                  let block = event["content_block"] as? [String: Any],
                  block["type"] as? String == "server_tool_use", block["name"] as? String == "web_search" {
            status = String(localized: "Searching the web...")
            if !spokeThisTurn { say(String(localized: "Let me look it up.")) }
        }
    }

    private static func isText(_ event: [String: Any]) -> Bool {
        (event["delta"] as? [String: Any])?["type"] as? String == "text_delta"
    }

    private func say(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let speak, !text.isEmpty else { return }
        speak(text)
        spokeThisTurn = true
    }

    /// Final reply. Speaks what is left; errors and refusals were never streamed, so they are spoken whole.
    private func finish(_ turn: Turn, _ reply: String) {
        turn.reply = reply
        say(spokeThisTurn ? unspoken : reply)
        unspoken = ""
    }

    /// Closes the current conversation: the screen clears, the next phrase starts a new one,
    /// and memory extraction of the finished one runs right away.
    func startNewChat(in context: ModelContext) {
        pendingClose?.cancel()
        let finished = chatID
        messages = []
        chatID = UUID()
        Task { await extract(chat: finished, in: context) }
    }

    /// Chats that still need the memory review, kept across app restarts.
    private static let pendingKey = "chatsToExtract"

    private static func markForExtraction(_ chat: UUID) {
        var pending = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
        if !pending.contains(chat.uuidString) { pending.append(chat.uuidString) }
        UserDefaults.standard.set(pending, forKey: pendingKey)
    }

    /// At launch: review the chats the app quit before reviewing (it closed within the chat window).
    func extractLeftovers(in context: ModelContext) {
        let leftovers = (UserDefaults.standard.stringArray(forKey: Self.pendingKey) ?? []).compactMap(UUID.init)
        for chat in leftovers where chat != chatID {
            Task { await extract(chat: chat, in: context) }
        }
    }

    /// Closes the conversation when the chat window passes without a new phrase.
    private func scheduleClose(after window: Double, in context: ModelContext) {
        pendingClose?.cancel()
        pendingClose = Task { [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard !Task.isCancelled else { return }
            self?.startNewChat(in: context)
            self?.timedOutAt = .now
        }
    }

    /// Asks Claude (structured output) what in the finished conversation is worth remembering, and applies it.
    private func extract(chat: UUID, in context: ModelContext) async {
        // Reviewed once, whatever the outcome: a failing chat must not be retried forever.
        defer {
            let pending = (UserDefaults.standard.stringArray(forKey: Self.pendingKey) ?? []).filter { $0 != chat.uuidString }
            UserDefaults.standard.set(pending, forKey: Self.pendingKey)
        }
        let turns = (try? context.fetch(FetchDescriptor<Turn>(
            predicate: #Predicate { $0.chatID == chat }, sortBy: [SortDescriptor(\.date)]))) ?? []
        guard !turns.isEmpty else { return }
        let memory = Memory(context: context)
        let transcript = turns.map { turn in
            "User: \(turn.user)\n" + turn.actions.map { "Sara did: \($0)\n" }.joined() + "Sara: \(turn.reply ?? "")"
        }.joined(separator: "\n\n")
        let request = memory.promptBlock() + "\n\n<conversation>\n\(transcript)\n</conversation>"

        guard let response = try? await claude.send(
                system: Self.extractionPrompt, messages: [["role": "user", "content": request]], schema: Self.extractionSchema),
              let result = try? JSONSerialization.jsonObject(with: Data(Claude.text(of: response).utf8)) as? [String: Any]
        else { return }
        for fact in result["save"] as? [[String: Any]] ?? [] {
            memory.save(name: fact["name"] as? String ?? "", type: fact["type"] as? String ?? "other", content: fact["content"] as? String ?? "")
        }
        for name in result["delete"] as? [String] ?? [] { memory.delete(name: name) }
    }

    /// "HassTurnOn" + {name: "Light"} -> "HassTurnOn name=Light"
    private static func describe(_ tool: String, _ args: [String: Any]) -> String {
        let params = args.keys.sorted().map { "\($0)=\(args[$0] ?? "")" }.joined(separator: ", ")
        return params.isEmpty ? tool : "\(tool) \(params)"
    }
}
