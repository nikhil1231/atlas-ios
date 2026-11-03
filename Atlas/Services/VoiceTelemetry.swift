import Foundation
import OSLog

struct PlaybackTiming {
    let item: String
    let renderedAt: TimeInterval
    let estimatedAudibleAt: TimeInterval
}

// Device-only, bounded diagnostic samples. No transcripts, audio, contents or credentials.
@MainActor
final class VoiceTelemetry {
    struct Sample { let name: String; let milliseconds: Double; let session: UUID; let turn: UUID }
    private let logger = Logger(subsystem: "ing.nikhil.noodle", category: "responsiveness")
    private(set) var samples: [Sample] = []
    private var session = UUID()
    private var turn = UUID()
    private var speechEnd: TimeInterval?
    private var localSpeechEnd: TimeInterval?
    private var recordedFirstAudio = false
    func reset() { session = UUID(); speechEnd = nil; localSpeechEnd = nil; recordedFirstAudio = false }
    func speechStopped(at now: TimeInterval = ProcessInfo.processInfo.systemUptime, localEnd: TimeInterval? = nil) {
        turn = UUID(); speechEnd = now; localSpeechEnd = localEnd; recordedFirstAudio = false
    }
    func playback(_ timing: PlaybackTiming) {
        guard !recordedFirstAudio, let speechEnd else { return }
        recordedFirstAudio = true
        record("speech_stop_received_to_first_render", timing.renderedAt - speechEnd)
        record("speech_stop_received_to_estimated_audible", timing.estimatedAudibleAt - speechEnd)
        if let localSpeechEnd, localSpeechEnd <= speechEnd, speechEnd - localSpeechEnd < 30 {
            record("local_speech_end_to_estimated_audible", timing.estimatedAudibleAt - localSpeechEnd)
        }
    }
    private func record(_ name: String, _ seconds: Double) {
        guard seconds >= 0, seconds < 120 else { return }
        let value = seconds * 1000
        samples.append(Sample(name: name, milliseconds: value, session: session, turn: turn))
        if samples.count > 200 { samples.removeFirst(samples.count - 200) }
        logger.info("metric=\(name, privacy: .public) ms=\(value, privacy: .public) session=\(self.session.uuidString, privacy: .public) turn=\(self.turn.uuidString, privacy: .public)")
    }
}

// RMS is an approximate local speech-end marker, not a second VAD that controls the conversation.
final class LocalSpeechClock: @unchecked Sendable {
    private let lock = NSLock()
    private var end: TimeInterval?
    func observe(_ pcm: Data, at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let count = pcm.count / 2
        guard count > 0 else { return }
        let energy = pcm.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Double in
            var sum = 0.0
            for i in 0..<count {
                let value = Double(Int16(bitPattern: UInt16(raw[i * 2]) | UInt16(raw[i * 2 + 1]) << 8)) / 32768
                sum += value * value
            }
            return sum / Double(count)
        }
        if energy > 0.0004 { lock.lock(); end = now; lock.unlock() }
    }
    func latest() -> TimeInterval? { lock.lock(); defer { lock.unlock() }; return end }
    func reset() { lock.lock(); end = nil; lock.unlock() }
}
