import AVFoundation
import Foundation

@MainActor
protocol VoiceAudioPlaying: AnyObject {
    var onPlaybackFinished: (() -> Void)? { get set }
    var onPlaybackStarted: ((PlaybackTiming) -> Void)? { get set }
    var hasPendingAudio: Bool { get }
    func start(onAudio: @escaping (Data) -> Void) throws
    func enqueue(_ data: Data, item: String)
    func interrupt() -> (String, Int)?
    func stop()
}

// Audio conversion stays on the engine's tap queue; no hardware-rate assumptions.
@MainActor
final class VoiceAudio: VoiceAudioPlaying {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    var onPlaybackFinished: (() -> Void)?
    var onPlaybackStarted: ((PlaybackTiming) -> Void)?
    private var renderWatch: Task<Void, Never>?
    private var observedItems: Set<String> = []
    private(set) var pendingBuffers = 0
    var hasPendingAudio: Bool { pendingBuffers > 0 }
    private var playbackGeneration = UUID()
    private var hasTap = false
    private var itemID: String?
    private var itemStartSample: AVAudioFramePosition = 0
    private var scheduledFrames: AVAudioFramePosition = 0

    func start(onAudio: @escaping (Data) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        do {
            try engine.inputNode.setVoiceProcessingEnabled(true)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
            let input = engine.inputNode.outputFormat(forBus: 0)
            guard input.sampleRate > 0,
                  let pcm = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000,
                                          channels: 1, interleaved: true),
                  let converter = AVAudioConverter(from: input, to: pcm) else {
                throw APIError(message: "Microphone audio format is unavailable.")
            }
            // Send 100 ms packets instead of a WebSocket message for every hardware tap.
            var packet = Data()
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: input) { buffer, _ in
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 24_000 / input.sampleRate) + 32
                guard let converted = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: capacity) else { return }
                var supplied = false
                var error: NSError?
                converter.convert(to: converted, error: &error) { _, status in
                    if supplied { status.pointee = .noDataNow; return nil }
                    supplied = true
                    status.pointee = .haveData
                    return buffer
                }
                guard error == nil, converted.frameLength > 0,
                      let samples = converted.int16ChannelData?[0] else { return }
                packet.append(Data(bytes: samples, count: Int(converted.frameLength) * 2))
                while packet.count >= 4_800 {
                    onAudio(Data(packet.prefix(4_800)))
                    packet.removeFirst(4_800)
                }
            }
            hasTap = true
            engine.prepare()
            try engine.start()
            player.play()
        } catch {
            stop()
            throw error
        }
    }
    func enqueue(_ data: Data, item: String) {
        let frames = data.count / 2
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(frames)),
              let samples = buffer.floatChannelData?[0] else { return }
        if itemID != item {
            itemID = item
            itemStartSample = scheduledFrames
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        // Explicit little-endian reads avoid unaligned loads of network Data.
        data.withUnsafeBytes { raw in
            for i in 0..<frames {
                let value = UInt16(raw[i * 2]) | UInt16(raw[i * 2 + 1]) << 8
                samples[i] = Float(Int16(bitPattern: value)) / 32768
            }
        }
        let firstSample = itemStartSample
        scheduledFrames += AVAudioFramePosition(frames)
        pendingBuffers += 1
        let generation = playbackGeneration
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, generation == self.playbackGeneration else { return }
                self.pendingBuffers -= 1
                if self.pendingBuffers == 0 { self.onPlaybackFinished?() }
            }
        }
        if !player.isPlaying { player.play() }
        if !observedItems.contains(item) {
            observedItems.insert(item)
            if observedItems.count > 100 { observedItems = [item] }
            renderWatch?.cancel()
            renderWatch = Task { [weak self] in
                // This observer exists only until the first rendered frame (at most two seconds).
                for _ in 0..<100 {
                    guard let self, !Task.isCancelled, self.playbackGeneration == generation else { return }
                    if let render = self.player.lastRenderTime,
                       let time = self.player.playerTime(forNodeTime: render), time.sampleTime > firstSample {
                        let renderedAt = AVAudioTime.seconds(forHostTime: render.hostTime)
                        self.onPlaybackStarted?(.init(item: item, renderedAt: renderedAt,
                            estimatedAudibleAt: renderedAt + self.engine.outputNode.presentationLatency))
                        return
                    }
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                }
            }
        }
    }
    func interrupt() -> (String, Int)? {
        let played = player.lastRenderTime.flatMap { player.playerTime(forNodeTime: $0) }?.sampleTime ?? 0
        let duration = max(0, min(played, scheduledFrames) - itemStartSample)
        let result = hasPendingAudio ? itemID.map { ($0, Int(duration * 1000 / 24_000)) } : nil
        renderWatch?.cancel(); renderWatch = nil
        observedItems.removeAll()
        playbackGeneration = UUID()
        pendingBuffers = 0
        player.stop()
        scheduledFrames = 0
        itemStartSample = 0
        itemID = nil
        player.play()
        return result
    }
    func stop() {
        renderWatch?.cancel(); renderWatch = nil
        observedItems.removeAll()
        playbackGeneration = UUID()
        pendingBuffers = 0
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        player.stop()
        engine.stop()
        if player.engine != nil { engine.detach(player) }
        itemID = nil
        scheduledFrames = 0
        itemStartSample = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
