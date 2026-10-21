import Foundation

/// Energy-based voice activity detector for one audio stream.
///
/// Fed one RMS level (dBFS) per frame. Tracks the noise floor as the minimum
/// level over a sliding window (speech always has short gaps, so the minimum
/// stays at the room's background level even during a long monologue), and
/// reports voice when the level clears the floor by `marginDB`.
public struct VoiceDetector {
    /// Levels below this never count as voice, however quiet the room is.
    public var minLevelDB: Float
    /// How far above the noise floor a frame must be to count as voice.
    public var marginDB: Float
    /// Keep reporting voice this long after the last loud frame, so the
    /// gaps between words don't split speech into fragments.
    public var hangover: TimeInterval
    /// Number of frames the noise floor is estimated over.
    public var floorWindow: Int

    public private(set) var noiseFloorDB: Float = -100
    private var history: [Float] = []
    private var lastVoiceAt: TimeInterval = -.greatestFiniteMagnitude

    public init(minLevelDB: Float = -48, marginDB: Float = 10, hangover: TimeInterval = 0.4, floorWindow: Int = 80) {
        self.minLevelDB = minLevelDB
        self.marginDB = marginDB
        self.hangover = hangover
        self.floorWindow = floorWindow
    }

    /// - Parameter extraMarginDB: added to the threshold for this frame, e.g.
    ///   to reject speaker bleed into the mic while the other side is talking.
    public mutating func process(levelDB raw: Float, at t: TimeInterval, extraMarginDB: Float = 0) -> Bool {
        let level = raw.isFinite ? max(raw, -100) : -100
        history.append(level)
        if history.count > floorWindow { history.removeFirst(history.count - floorWindow) }
        noiseFloorDB = history.min() ?? -100

        let threshold = max(minLevelDB, noiseFloorDB + marginDB) + extraMarginDB
        if level >= threshold { lastVoiceAt = t }
        return t - lastVoiceAt <= hangover
    }

    public mutating func reset() {
        history.removeAll()
        noiseFloorDB = -100
        lastVoiceAt = -.greatestFiniteMagnitude
    }
}
