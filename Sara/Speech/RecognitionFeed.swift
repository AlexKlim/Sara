import AVFoundation
import Speech

/// Hands microphone buffers from the audio thread to the current recognition request.
/// The microphone tap is installed once, before the engine starts (with voice processing on,
/// a tap added to a running engine gets no audio); recognitions come and go through this.
final class RecognitionFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock { self.request = request }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request }?.append(buffer)
    }
}
