import SwiftData
import SwiftUI

/// Root screen: the panel by day, the night clock by night, talking to Sara on top, "done" alerts over everything.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Turn.date) private var allTurns: [Turn]
    @State private var sara = Sara()
    @State private var voice = Voice()
    @State private var home = Home()
    /// The panel follows its saved JSON, so lists Sara adds and editor changes show up right away.
    @AppStorage("panel") private var panelData: Data?
    private var panel: Panel { Panel.decoded(panelData) }
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
    @State private var unconfirmedSetupLink: SetupLink?
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
                    .onTapGesture { awakeUntil = .now + 120 }
                    .onAppear { PowerSaver.shared.night = true }
            } else {
                PanelView(
                    home: home, panel: panel,
                    lastTurn: allTurns.last { $0.chatID == sara.chatID },
                    listening: wakeEnabled,
                    onTalk: { showTalk = true }, onSettings: { showSettings = true })
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
        .sheet(isPresented: $showSettings, onDismiss: { CloudSettings.pushAll(); home.start(); applyWakeWord(); buildPanelIfEmpty() }) { SettingsView().presentationSizing(.page) }
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            guard let link = SetupLink(url: url) else { return }
            showSettings = false
            showTalk = false
            // ponytail: fixed delay for the sheet to close, an alert can't show over it.
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                unconfirmedSetupLink = link
            }
        }
        .alert("Connect to this home?", isPresented: Binding(get: { unconfirmedSetupLink != nil }, set: { if !$0 { unconfirmedSetupLink = nil } }), presenting: unconfirmedSetupLink) { link in
            Button("Connect") {
                link.apply()
                home.start()
                buildPanelIfEmpty()
            }
            Button("Cancel", role: .cancel) {}
        } message: { link in
            Text("Home Assistant: \(link.homeHost). The keys on this device are replaced with the ones from the code.")
        }
        .onAppear {
            Keychain.moveLocalSecretsToICloud()
            CloudSettings.start()
            UIApplication.shared.isIdleTimerDisabled = PowerSaver.isWallPanel
            home.start()
            Alarms.shared.start()
            PowerSaver.shared.start()
            sara.extractLeftovers(in: context)
            // A timer or alarm rang while Sara is on screen: say it and show the card.
            Alarms.shared.onFire = { label in
                PowerSaver.shared.activity()
                done = label
                if !isNight(.now) { voice.say(String(localized: "Timer: \(label)")) }
            }
            applyWakeWord()
            if haURL.isEmpty { showSettings = true }
            buildPanelIfEmpty()
        }
        // The conversation ran out: back to the panel.
        .onChange(of: sara.timedOutAt) { showTalk = false }
        .onChange(of: done) { if done != nil { PowerSaver.shared.activity() } }
        .onChange(of: scenePhase) {
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
    private func respond(_ text: String, spoken: Bool, followUp: Bool = false) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        PowerSaver.shared.activity()
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
        // A new answer: speech of an earlier, interrupted one is dropped.
        let token = voice.newSpeech()
        var say: ((String) -> Void)? = speak ? { voice.say($0, token: token) } : nil
        if speak, !speaker.isEmpty {
            // A Home Assistant speaker (e.g. Yandex Station) gets the whole reply. If it fails, this device speaks.
            // Voice filters out its words and lets the user interrupt it while it reads, about 14 characters a second.
            say = { phrase in
                voice.speakingExternally(phrase, for: Double(phrase.count) / 14 + 1)
                Task { do { try await home.say(Voice.speakable(phrase), on: speaker) } catch { voice.say(phrase) } }
            }
        }
        let task = Task { [followUp] in
            _ = await previous?.value // a cancelled request cleans up first
            return await sara.ask(text, in: context, speak: say, bySentence: speaker.isEmpty, withoutWakeWord: followUp)
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

    /// First run: build the panel from Home Assistant areas, so a new user sees their home right away.
    private func buildPanelIfEmpty() {
        let yandexToken = Keychain.get("yandexToken")
        guard panel.blocks.isEmpty, !haURL.isEmpty || !yandexToken.isEmpty else { return }
        Task {
            // Home Assistant first; a home with only Yandex gets its rooms from there.
            var built = haURL.isEmpty ? nil : try? await Panel.build(from: HomeAssistantSocket(baseURL: haURL, token: Keychain.get("haToken")))
            if built?.blocks.isEmpty ?? true, !yandexToken.isEmpty, let info = try? await YandexHome(token: yandexToken).info() {
                built = Panel.build(fromYandex: info)
            }
            guard let built, !built.blocks.isEmpty else { return }
            built.save()
        }
    }

    private func applyWakeWord() {
        let speaker = speakerEntity.trimmingCharacters(in: .whitespaces)
        voice.onStopExternal = speaker.isEmpty ? nil : { Task { await home.stop(speaker) } }
        guard wakeEnabled else { voice.stopListening(); return }
        let word = wakeWord.trimmingCharacters(in: .whitespaces)
        Task {
            await voice.listen(for: word.isEmpty ? String(localized: "Sara") : word,
                               onWake: { PowerSaver.shared.activity(); showTalk = true },
                               onCommand: { respond($0, spoken: true, followUp: $1) })
        }
    }

    private func isNight(_ date: Date) -> Bool {
        guard nightEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        return nightStart > nightEnd ? hour >= nightStart || hour < nightEnd : hour >= nightStart && hour < nightEnd
    }
}
