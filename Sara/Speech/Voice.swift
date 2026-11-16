import AVFoundation
import Speech

/// Speech in and out, in the device language: push-to-talk, or always-on listening for a wake word.
/// Recognition runs on the device when the language supports it.
/// Sara's voice plays through the same audio engine as the microphone, with Apple's voice processing on,
/// so her own voice is cancelled from what the microphone hears and the user can interrupt her.
@MainActor @Observable final class Voice {
    /// Recording a phrase: after a mic tap, the wake word, or right after an answer.
    private(set) var listening = false
    /// The phrase heard so far. In wake mode, only the part after the wake word.
    private(set) var text = ""
    /// Sara's voice is playing, here or on a Home Assistant speaker.
    var speaking: Bool { playing || Date.now < externalUntil }
    /// Stops a Home Assistant speaker when the user interrupts it.
    var onStopExternal: (() -> Void)?
    private var playing = false
    /// A Home Assistant speaker is (probably) reading Sara's answer until then.
    private var externalUntil = Date.distantPast

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let recognizer = SFSpeechRecognizer()
    private let synthesizer = AVSpeechSynthesizer()
    private var engineReady = false
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let feed = RecognitionFeed()
    /// Callbacks of an old recognition task are ignored.
    private var generation = 0
    private var started = Date.now
    private var pushToTalk = false

    private var wakeWord: String?
    private var onWake: (() -> Void)?
    /// The command, and whether it came without the wake word (a follow-up).
    private var onCommand: ((String, Bool) -> Void)?
    private var heardWakeWord = false
    /// This recognition overlapped Sara's voice: words she said are filtered out as echo.
    private var heardSara = false
    private var silence: Task<Void, Never>?
    private var followUpUntil = Date.distantPast
    /// The follow-up window from before Sara started working, to return to if the phrase was not for her.
    private var windowBeforeWork = Date.distantPast

    /// Speech out: bumping the token drops queued and incoming speech (after an interruption).
    private var speechToken = 0
    private var pendingBuffers = 0
    /// Words Sara is saying now, to tell her echo from the user.
    private var spokenWords = Set<String>()
    private var playerFormat: AVAudioFormat?
    /// Single words that stop Sara while she speaks, without the wake word. Localized, comma-separated.
    private static let stopWords = Set(String(localized: "stop, cancel, enough").split(separator: ",").map { word($0) })

    // MARK: Push-to-talk

    func start() async {
        guard await authorized() else { return }
        stopSpeaking()
        pushToTalk = true
        begin()
        listening = true
    }

    /// Stops listening and returns what was heard. Wake word listening, if on, goes on.
    func stop() -> String {
        let phrase = text
        pushToTalk = false
        listening = false
        if wakeWord != nil { begin() } else { endRecognition() }
        return phrase
    }

    // MARK: Wake word and follow-ups

    /// Listens all the time. On the wake word calls `onWake`; after a pause, `onCommand` with the rest of the phrase.
    func listen(for word: String, onWake: @escaping () -> Void, onCommand: @escaping (String, Bool) -> Void) async {
        wakeWord = word.lowercased()
        self.onWake = onWake
        self.onCommand = onCommand
        guard await authorized() else { return }
        if !pushToTalk { begin() }
    }

    func stopListening() {
        wakeWord = nil
        if !pushToTalk { endRecognition() }
    }

    /// After a spoken answer, listen for a follow-up without the wake word: once Sara is quiet, for `seconds`.
    func followUp(for seconds: Double) {
        guard wakeWord != nil, !pushToTalk, seconds > 0 else { return }
        Task { [weak self] in
            while let self, self.speaking {
                try? await Task.sleep(for: .seconds(0.3))
            }
            self?.followUpUntil = .now + seconds
            self?.resumeFollowUp()
        }
    }

    /// While Sara works on a spoken phrase, listen without the wake word, so the user can add to it or say "ok, thanks".
    func keepListening() {
        windowBeforeWork = followUpUntil
        followUpUntil = .now + 60
        resumeFollowUp()
    }

    /// The phrase was not for Sara: listen on for what was left of the window before it.
    func restoreFollowUp() {
        followUpUntil = windowBeforeWork
        if followUpUntil.timeIntervalSinceNow > 0.5 { resumeFollowUp() } else { endFollowUp() }
    }

    /// The conversation is over: back to waiting for the wake word.
    func endFollowUp() {
        followUpUntil = .distantPast
        guard !pushToTalk, wakeWord != nil, text.isEmpty else { return }
        listening = false
        begin()
    }

    /// Listen on until the follow-up window ends.
    func resumeFollowUp() {
        let left = followUpUntil.timeIntervalSinceNow
        // Already taking down a phrase (e.g. the user interrupted Sara): don't drop it.
        guard wakeWord != nil, !pushToTalk, left > 0.5, text.isEmpty else { return }
        begin()
        listening = true
        waitForSilence(left)
    }

    /// A Home Assistant speaker reads `phrase` for about `seconds`. Its sound does not go through this device,
    /// so echo cancellation can't remove it: its words are filtered out like echo, and the user can still interrupt.
    func speakingExternally(_ phrase: String, for seconds: Double) {
        spokenWords.formUnion(Self.words(phrase))
        externalUntil = max(externalUntil, .now) + seconds
    }

    // MARK: Speech out

    /// A token for the next answer. Speech with an older token is dropped.
    func newSpeech() -> Int {
        speechToken += 1
        spokenWords = []
        return speechToken
    }

    /// Text for speech: without quotes and backslashes, which the iOS voice reads out as "backslash".
    /// Apostrophes stay ("don't").
    static func speakable(_ text: String) -> String {
        text.filter { !"«»\"“”„‟\\".contains($0) }
    }

    func say(_ phrase: String, token: Int? = nil) {
        let phrase = Self.speakable(phrase)
        #if DEBUG
        print("[voice] say:", phrase, "token:", token ?? -1, "current:", speechToken)
        #endif
        guard token == nil || token == speechToken, startEngine() else { return }
        let token = speechToken
        spokenWords.formUnion(Self.words(phrase))
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        // Synthesize into buffers and play them through the engine, so echo cancellation knows Sara's voice.
        synthesizer.write(utterance) { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.play(pcm, token: token) } }
        }
    }

    func stopSpeaking() {
        speechToken += 1
        synthesizer.stopSpeaking(at: .immediate)
        if engineReady {
            player.stop()
            player.play()
        }
        pendingBuffers = 0
        playing = false
        if Date.now < externalUntil {
            externalUntil = .distantPast
            onStopExternal?()
        }
    }

    private func play(_ buffer: AVAudioPCMBuffer, token: Int) {
        guard token == speechToken, let buffer = Self.float(buffer) else { return }
        // Voices differ in sample rate: plug the player in with the voice's format, the mixer converts the rate.
        if playerFormat != buffer.format {
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            playerFormat = buffer.format
            player.play()
            #if DEBUG
            print("[voice] speech format:", buffer.format)
            #endif
        }
        pendingBuffers += 1
        playing = true
        player.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.played(token) } }
        }
    }

    private func played(_ token: Int) {
        guard token == speechToken else { return }
        pendingBuffers = max(pendingBuffers - 1, 0)
        if pendingBuffers == 0 { playing = false }
    }

    /// The synthesizer may give 16-bit samples; the player takes float. Same sample rate, so no resampling.
    private static func float(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format.commonFormat == .pcmFormatFloat32, !buffer.format.isInterleaved { return buffer }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: buffer.format.sampleRate, channels: buffer.format.channelCount),
              let converter = AVAudioConverter(from: buffer.format, to: format),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
              (try? converter.convert(to: output, from: buffer)) != nil
        else {
            #if DEBUG
            print("[voice] can't convert speech from", buffer.format)
            #endif
            return nil
        }
        return output
    }

    // MARK: Engine and recognition

    private func authorized() async -> Bool {
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        return speech ? await AVAudioApplication.requestRecordPermission() : false
    }

    /// The engine runs all the time: the microphone with voice processing, and Sara's voice.
    private func startEngine() -> Bool {
        if engineReady { return true }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try? session.setActive(true)
        do { try engine.inputNode.setVoiceProcessingEnabled(true) } catch {
            #if DEBUG
            print("[voice] voice processing failed:", error)
            #endif
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        installMicTap()
        engine.prepare()
        do { try engine.start() } catch {
            #if DEBUG
            print("[voice] engine failed:", error)
            #endif
            return false
        }
        player.play()
        engineReady = true
        // iOS reconfigures audio right after voice processing comes on (and on route changes) and stops the engine.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartEngine() }
        }
        #if DEBUG
        print("[voice] engine started, voice processing:", engine.inputNode.isVoiceProcessingEnabled, "input:", engine.inputNode.outputFormat(forBus: 0))
        #endif
        return true
    }

    /// The microphone tap goes in before the engine starts. Recognitions get audio through `feed`.
    /// The format is read now: voice processing and route changes may change it (some devices get 5 channels).
    private func installMicTap() {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let feed = feed
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            feed.append(buffer)
        }
    }

    private func restartEngine() {
        guard !engine.isRunning else { return }
        installMicTap()
        engine.prepare()
        try? engine.start()
        player.play()
        #if DEBUG
        print("[voice] engine restarted after a configuration change, running:", engine.isRunning)
        #endif
    }

    /// Starts a fresh recognition: the old transcript is dropped.
    private func begin() {
        guard startEngine() else { return }
        endRecognition()
        guard let recognizer, recognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        text = ""
        heardWakeWord = false
        heardSara = false
        started = .now
        generation += 1
        let current = generation

        feed.set(request)
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let phrase = result?.bestTranscription.formattedString
            let done = error != nil || result?.isFinal == true
            #if DEBUG
            if let error { print("[voice] error:", error) }
            #endif
            Task { @MainActor in self?.heard(phrase, done: done, generation: current) }
        }
    }

    private func endRecognition() {
        silence?.cancel()
        feed.set(nil)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func heard(_ phrase: String?, done: Bool, generation current: Int) {
        guard current == generation else { return }
        #if DEBUG
        print("[voice] heard:", phrase ?? "-", "done:", done, "listening:", listening, "speaking:", speaking)
        #endif
        if pushToTalk {
            if let phrase { text = phrase }
            return
        }
        guard let word = wakeWord else { return }

        // Recognition ended by itself (time limit, error): keep listening.
        if done { finish(); return }
        guard let phrase, !phrase.isEmpty else { return }

        let lower = phrase.lowercased()
        let wakeRange = lower.range(of: word, options: .backwards)
        if speaking {
            heardSara = true
            // What leaks through echo cancellation is Sara's own words. Interrupt her only on the wake word
            // or on words she is not saying: two, or three for a Home Assistant speaker (no echo cancellation there).
            let own = Self.words(phrase).filter { !spokenWords.contains($0) }
            // "Stop", "cancel": just stop talking. Nothing goes to Claude, the follow-up window opens as usual.
            if !own.isDisjoint(with: Self.stopWords) {
                stopSpeaking()
                begin()
                return
            }
            guard wakeRange != nil || own.count >= (playing ? 2 : 3) else { return }
            stopSpeaking()
            listening = true
        }

        let trim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        var said: String
        if let wakeRange {
            heardWakeWord = true
            if !listening {
                listening = true
                onWake?()
            }
            // ponytail: assumes lowercasing keeps the length, true for Russian and English
            said = String(phrase.suffix(lower.distance(from: wakeRange.upperBound, to: lower.endIndex)))
        } else if listening {
            // A follow-up right after Sara's answer: no wake word needed.
            said = phrase
        } else {
            // No wake word yet. Restart now and then to keep the transcript short.
            if Date.now.timeIntervalSince(started) > 50 { begin() }
            return
        }
        if heardSara {
            said = said.split(separator: " ").filter { !spokenWords.contains(Self.word($0)) }.joined(separator: " ")
        }
        text = said.trimmingCharacters(in: trim)
        // The command ends after a pause. Right after the bare wake word, wait longer.
        waitForSilence(text.isEmpty ? 6 : 1.5)
    }

    private func waitForSilence(_ seconds: Double) {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// Hands over the command (if any) and listens for the next wake word.
    private func finish() {
        let command = listening ? text : ""
        let followUp = !heardWakeWord
        listening = false
        begin()
        if !command.isEmpty { onCommand?(command, followUp) }
    }

    private static func words(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(word))
    }

    private static func word(_ text: Substring) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
