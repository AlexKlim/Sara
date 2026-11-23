import SwiftData
import SwiftUI

/// Root screen: the panel by day, the night clock by night, talking to Sara on top, "done" alerts over everything.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(Turn.latest) private var latestTurns: [Turn]
    @State private var sara = Sara()
    @State private var voice = Voice()
    @State private var home = Home()
    /// The panel follows its saved JSON, so lists Sara adds and editor changes show up right away.
    @AppStorage("panel") private var panelData: Data?
    @State private var panel = Panel.load()
    @State private var showTalk = false
    @State private var showSettings = false
    /// A tap at night wakes the panel for a while.
    @State private var awakeUntil = Date.distantPast
    @State private var done: String?
    /// The phrase Sara is working on, so the user can barge in and add to it.
    @State private var inFlight: Task<Sara.Outcome, Never>?
    @State private var inFlightText = ""
    @State private var inFlightFollowUp = false
    /// A phrase said while Sara was already acting or answering: handled right after her.
    @State private var queued: (text: String, followUp: Bool)?
    @State private var pausedMusicOn: String?
    @State private var pausingMusic = false
    /// The chat that was told about a music pause, so it also hears when the pause is over.
    @State private var musicNoteChat: UUID?
    @AppStorage("haURL") private var haURL = ""
    @AppStorage("nightStart") private var nightStart = 23
    @AppStorage("nightEnd") private var nightEnd = 10
    @AppStorage("nightEnabled") private var nightEnabled = PowerSaver.isWallPanel
    @AppStorage("speakerEntity") private var speakerEntity = ""
    @AppStorage("wakeEnabled") private var wakeEnabled = true
    @AppStorage("wakeWord") private var wakeWord = ""
    @AppStorage("followUpSeconds") private var followUpSeconds = 20.0

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            if isNight(timeline.date) && timeline.date > awakeUntil {
                NightView(home: home, panel: panel, endHour: nightEnd)
                    .onTapGesture { wakePanel() }
                    .onAppear { PowerSaver.shared.night = true }
            } else {
                let lastTurn = latestTurns.first { $0.chatID == sara.chatID }
                Group {
                    if !PowerSaver.isWallPanel {
                        PhoneView(home: home, panel: panel, lastTurn: lastTurn, date: timeline.date, onTalk: { showTalk = true }, onSettings: { showSettings = true })
                    } else {
                        PanelView(
                            home: home, panel: panel, lastTurn: lastTurn, listening: wakeEnabled,
                            onTalk: { showTalk = true }, onSettings: { showSettings = true })
                    }
                }
                .onAppear { PowerSaver.shared.night = false }
            }
        }
        // Any touch counts as someone being here.
        .simultaneousGesture(TapGesture().onEnded { PowerSaver.shared.activity() })
        // The first touch on a dimmed panel only wakes it, so a tile under the finger is not toggled in the dark.
        .overlay {
            if PowerSaver.shared.idle && !PowerSaver.shared.night {
                Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { PowerSaver.shared.activity() }
            }
        }
        .overlay { if let done { DoneAlertView(name: done) { self.done = nil } } }
        .fullScreenCover(isPresented: $showTalk) {
            TalkView(sara: sara, voice: voice, onAsk: { respond($0, spoken: $1) })
        }
        .sheet(isPresented: $showSettings, onDismiss: { home.start(); applyWakeWord(); buildPanelIfEmpty() }) {
            SettingsView().presentationSizing(.page)
        }
        .preferredColorScheme(.dark)
        .onChange(of: haURL) {
            home.start()
            if PowerSaver.isWallPanel { BatteryReporter.report() }
        }
        .onChange(of: panelData) { panel = Panel.decoded(panelData) }
        .onChange(of: home.saraAsleep) { applyWakeWord() }
        // Entities come and go when a device is added: look for new devices then, and on every start.
        .onChange(of: home.entityIDs, initial: true) { Task { await NewDevices.shared.check() } }
        .onAppear {
            Keychain.moveLocalSecretsToICloud()
            CloudSettings.start()
            UIApplication.shared.isIdleTimerDisabled = PowerSaver.isWallPanel
            home.start()
            Alarms.shared.start()
            PowerSaver.shared.start()
            if PowerSaver.isWallPanel { BatteryReporter.start() }
            Weather.shared.start(home: home)
            sara.extractLeftovers(in: context)
            // A timer or alarm rang while Sara is on screen: say it and show the card.
            Alarms.shared.onFire = { label in
                done = label
                if !isNight(.now) { voice.say(String(localized: "Timer: \(label)")) }
            }
            // A scheduled command is due: Sara does it silently, after whatever she is doing, and the panel shows it.
            Alarms.shared.onCommand = { command in
                Task {
                    while sara.busy { try? await Task.sleep(for: .seconds(1)) }
                    // Closed while waiting: missed, like any command that comes due with the app closed.
                    guard UIApplication.shared.applicationState == .active else { return }
                    respond(command, spoken: false, scheduled: true)
                }
            }
            NewDevices.shared.onFound = { device in
                if !home.saraAsleep && !isNight(.now) { voice.say(String(localized: "A new device appeared: \(device.name). You can add it to the panel.")) }
            }
            // Sara changed how she listens or speaks: restart listening once she has finished answering
            // and the follow-up is over, so its timeout is kept.
            AppSettings.onVoiceChange = {
                Task {
                    while sara.busy || voice.speaking || voice.listening { try? await Task.sleep(for: .seconds(1)) }
                    applyWakeWord()
                }
            }
            applyWakeWord()
            if haURL.isEmpty { showSettings = true }
            buildPanelIfEmpty()
        }
        // The conversation ran out: back to the panel.
        .onChange(of: sara.timedOutAt) { showTalk = false }
        // An open dialog means Sara hears you without the wake word: when she stops listening, back to the panel.
        // The delay lets a finished phrase turn into work before the check.
        .onChange(of: voice.listening) {
            guard !voice.listening, wakeEnabled else { return }
            Task {
                try? await Task.sleep(for: .seconds(1))
                if !voice.listening, !sara.busy, !voice.speaking, queued == nil { showTalk = false }
            }
        }
        .onChange(of: done) { if done != nil { wakePanel() } }
        .onChange(of: scenePhase) {
            Log.write("[app] \(scenePhase)")
            if scenePhase == .active { PowerSaver.shared.activity() } else { PowerSaver.shared.restoreBrightness() }
        }
        .onChange(of: running) { old, new in
            // A device that was running and stopped: show "done".
            if let finished = old.subtracting(new).first,
               let item = panel.blocks.flatMap(\.items).first(where: { $0.entity == finished }) {
                done = home.name(item)
            }
        }
    }

    private var running: Set<String> {
        Set(panel.blocks.filter { $0.kind == .running }.flatMap(\.items).filter(home.isRunning).map(\.entity))
    }

    /// Sends a phrase to Sara. A spoken phrase gets a spoken answer, except at night.
    /// `followUp`: heard without the wake word, so Sara may decide it was not for her.
    /// `scheduled`: a command the user set for now; it doesn't wake the panel.
    private func respond(_ text: String, spoken: Bool, followUp: Bool = false, scheduled: Bool = false) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if !scheduled { PowerSaver.shared.activity() }
        var text = text, followUp = followUp
        let previous = inFlight
        if sara.busy {
            // A single word without the wake word while Sara works is most likely noise or the TV, not an addition.
            if followUp, text.split(separator: " ").count < 2 { return }
            // Barge-in: Sara has not acted or answered yet, so cancel and send both phrases as one.
            // Otherwise the phrase waits for her to finish: redoing the request could repeat an action.
            guard sara.canInterrupt, let previous else {
                queued = (text: [queued?.text, text].compactMap { $0 }.joined(separator: "\n"),
                          followUp: (queued?.followUp ?? true) && followUp)
                return
            }
            previous.cancel()
            text = inFlightText + "\n" + text
            followUp = inFlightFollowUp && followUp
        }
        let speak = spoken && !isNight(.now)
        let speaker = speakerEntity.trimmingCharacters(in: .whitespaces)
        // A new answer: speech of an earlier, interrupted one is dropped. Silent scheduled work leaves speech playing.
        let token = scheduled ? 0 : voice.newSpeech()
        var say: ((String) -> Void)? = speak ? { voice.say($0, token: token) } : nil
        if speak, !speaker.isEmpty {
            // A Home Assistant speaker (e.g. Yandex Station) gets the whole reply. If it fails, this device speaks.
            // Voice filters out its words and lets the user interrupt it while it reads, about 14 characters a second.
            say = { phrase in
                voice.speakingExternally(phrase, for: Double(phrase.count) / 14 + 1)
                Task {
                    do { try await home.say(Voice.speakable(phrase), on: speaker) } catch {
                        #if DEBUG
                        print("[speaker] \(speaker) failed:", error)
                        #endif
                        voice.say(phrase)
                    }
                }
            }
        }
        let task = Task { [followUp] in
            _ = await previous?.value // a cancelled request cleans up first
            // The pause may still be on its way to Home Assistant; the note has to match how it ends.
            var waited = 0
            while pausingMusic, pausedMusicOn == nil, waited < 20 {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
            }
            let note = scheduled ? Sara.scheduledNote : musicNote
            let outcome = await sara.ask(text, in: context, speak: say, bySentence: speaker.isEmpty, withoutWakeWord: followUp, note: note)
            if !scheduled, note != nil { musicNoteChat = pausedMusicOn == nil ? nil : sara.chatID }
            return outcome
        }
        inFlight = task
        inFlightText = text
        inFlightFollowUp = followUp
        if spoken { voice.keepListening() }
        Task {
            let outcome = await task.value
            if let next = queued {
                queued = nil
                respond(next.text, spoken: true, followUp: next.followUp)
                return
            }
            guard spoken else { return }
            switch outcome {
            case .answered: voice.followUp(for: followUpSeconds)
            case .ignored: voice.restoreFollowUp()
            case .ended: voice.endFollowUp(); showTalk = false
            case .interrupted: break
            }
        }
    }

    private var musicNote: String? {
        if let player = pausedMusicOn {
            return Sara.musicPausedNote.replacingOccurrences(of: "{player}", with: home.attribute(player, "friendly_name") as? String ?? player)
        }
        return musicNoteChat == sara.chatID ? Sara.musicResumedNote : nil
    }

    private func pauseMusic() {
        let speaker = speakerEntity.trimmingCharacters(in: .whitespaces)
        // While the speaker reads Sara's own reply it is "playing" too, and that is not music.
        guard pausedMusicOn == nil, !pausingMusic, !speaker.isEmpty, home.state(speaker) == "playing", !voice.speaking else { return }
        pausingMusic = true
        let pausedAt = Date.now
        Task {
            defer { pausingMusic = false }
            guard await home.pause(speaker) else { return }
            pausedMusicOn = speaker
            var quietSince = Date.now
            while true {
                try? await Task.sleep(for: .seconds(1))
                if voice.listening || sara.busy || voice.speaking { quietSince = .now }
                if Date.now.timeIntervalSince(quietSince) > 3 { break }
            }
            pausedMusicOn = nil
            // "Sara, stop the music": she handled the player herself, so it stays as she left it.
            let name = home.attribute(speaker, "friendly_name") as? String ?? speaker
            let handled = latestTurns.filter { $0.date >= pausedAt }.flatMap(\.actions)
                .filter { !$0.hasPrefix("web_search") }
                .contains { $0.hasPrefix("HassMedia") || $0.contains(speaker) || $0.localizedCaseInsensitiveContains(name) }
            await home.refresh()
            guard !handled, home.state(speaker) == "paused" else { return }
            for _ in 0..<3 {
                if await home.resume(speaker) { return }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func wakePanel() {
        awakeUntil = .now + 120
        PowerSaver.shared.activity()
    }

    /// First run: build the panel from Home Assistant areas, so a new user sees their home right away.
    private func buildPanelIfEmpty() {
        let yandexToken = Keychain.get("yandexToken")
        let url = haURL
        guard panel.blocks.isEmpty, !url.isEmpty || !yandexToken.isEmpty else { return }
        Task {
            // Home Assistant first; a home with only Yandex gets its rooms from there.
            var built = url.isEmpty ? nil : try? await Panel.build(from: HomeAssistantSocket(baseURL: url, token: Keychain.get("haToken")))
            if built?.blocks.isEmpty ?? true, !yandexToken.isEmpty, let info = try? await YandexHome(token: yandexToken).info() {
                built = Panel.build(fromYandex: info)
            }
            guard let built, !built.blocks.isEmpty, url == haURL, panel.blocks.isEmpty else { return }
            built.save()
        }
    }

    private func applyWakeWord() {
        let speaker = speakerEntity.trimmingCharacters(in: .whitespaces)
        voice.onStopExternal = speaker.isEmpty ? nil : { Task { await home.stop(speaker) } }
        guard wakeEnabled, !home.saraAsleep else { voice.stopListening(); return }
        let word = wakeWord.trimmingCharacters(in: .whitespaces)
        Task {
            await voice.listen(for: word.isEmpty ? String(localized: "Sara") : word,
                               onWake: { wakePanel(); pauseMusic(); showTalk = true },
                               onCommand: { respond($0, spoken: true, followUp: $1) })
        }
    }

    private func isNight(_ date: Date) -> Bool {
        guard nightEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        return nightStart > nightEnd ? hour >= nightStart || hour < nightEnd : hour >= nightStart && hour < nightEnd
    }
}
