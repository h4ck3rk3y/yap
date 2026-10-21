import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Collects sample energy from an audio callback thread; drained once per tick.
final class LevelAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var sumSquares: Double = 0
    private var count = 0

    func add(_ samples: UnsafePointer<Float>, count n: Int) {
        guard n > 0 else { return }
        var sum: Double = 0
        for i in 0..<n {
            let s = Double(samples[i])
            sum += s * s
        }
        lock.lock()
        sumSquares += sum
        count += n
        lock.unlock()
    }

    /// RMS level in dBFS of everything since the last drain, or -100 if nothing arrived.
    func drainDB() -> Float {
        lock.lock()
        defer { sumSquares = 0; count = 0; lock.unlock() }
        guard count > 0 else { return -100 }
        let meanSquare = sumSquares / Double(count)
        return meanSquare > 0 ? Float(10 * log10(meanSquare)) : -100
    }
}

/// Your side of the conversation: the default input device.
final class MicCapture {
    let levels = LevelAccumulator()
    private var engine = AVAudioEngine()
    private var configObserver: NSObjectProtocol?
    private var voiceProcessing = false

    func start(voiceProcessing: Bool) throws {
        self.voiceProcessing = voiceProcessing
        try startEngine()
        // Headphones plugged in / AirPods connected: the engine stops, so rebuild it.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, (note.object as? AVAudioEngine) === self.engine else { return }
            self.teardownEngine()
            try? self.startEngine()
        }
    }

    func stop() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        teardownEngine()
    }

    private func startEngine() throws {
        engine = AVAudioEngine()
        let input = engine.inputNode
        if voiceProcessing {
            // Echo cancellation, for laptop speakers without headphones.
            try input.setVoiceProcessingEnabled(true)
            input.voiceProcessingOtherAudioDuckingConfiguration =
                .init(enableAdvancedDucking: false, duckingLevel: .min)
            _ = engine.mainMixerNode
        }
        let format = input.outputFormat(forBus: 0)
        let levels = self.levels
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            levels.add(channels[0], count: Int(buffer.frameLength))
        }
        engine.prepare()
        try engine.start()
    }

    private func teardownEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

/// The other side of the conversation: everything the Mac is playing
/// (Zoom, Meet, Teams, …), captured via ScreenCaptureKit.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let levels = LevelAccumulator()
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "yap.system-audio")

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "Yap", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display to capture audio from"])
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 1
        // We only want audio; keep the video side as cheap as possible.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        Task { try? await stream.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        try? sampleBuffer.withAudioBufferList { buffers, _ in
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let n = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                levels.add(data.assumingMemoryBound(to: Float.self), count: n)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
    }
}
