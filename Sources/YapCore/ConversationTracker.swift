import Foundation

/// Accumulates who-spoke-when into talk totals and tracks your current
/// uninterrupted turn ("monologue").
///
/// A monologue starts when you start speaking and survives short pauses and
/// backchannel ("mhm", "right") from the other side. It ends when the other
/// side holds the floor for `floorTakeover` seconds while you're quiet, or
/// when you leave a pause of `turnEndSilence` seconds.
public struct ConversationTracker {
    public var turnEndSilence: TimeInterval
    public var floorTakeover: TimeInterval
    /// Window for the rolling "recent" talk ratio.
    public var recentWindow: TimeInterval

    public private(set) var meTotal: TimeInterval = 0
    public private(set) var themTotal: TimeInterval = 0
    public private(set) var overlapTotal: TimeInterval = 0
    public private(set) var longestMonologue: TimeInterval = 0
    public private(set) var monologueStart: TimeInterval?
    public private(set) var isMeSpeaking = false
    public private(set) var isThemSpeaking = false

    private var now: TimeInterval = 0
    private var lastMeAt: TimeInterval = 0
    private var themRunStart: TimeInterval?

    private struct Sample { var t: TimeInterval; var me: TimeInterval; var them: TimeInterval }
    private var recent: [Sample] = []
    private var recentMe: TimeInterval = 0
    private var recentThem: TimeInterval = 0

    public init(turnEndSilence: TimeInterval = 3, floorTakeover: TimeInterval = 1, recentWindow: TimeInterval = 300) {
        self.turnEndSilence = turnEndSilence
        self.floorTakeover = floorTakeover
        self.recentWindow = recentWindow
    }

    /// Record one frame of `dt` seconds ending at `t`.
    public mutating func update(me: Bool, them: Bool, at t: TimeInterval, dt: TimeInterval) {
        now = t
        isMeSpeaking = me
        isThemSpeaking = them
        if me { meTotal += dt }
        if them { themTotal += dt }
        if me && them { overlapTotal += dt }

        let sample = Sample(t: t, me: me ? dt : 0, them: them ? dt : 0)
        recent.append(sample)
        recentMe += sample.me
        recentThem += sample.them
        var drop = 0
        while drop < recent.count, t - recent[drop].t >= recentWindow {
            recentMe -= recent[drop].me
            recentThem -= recent[drop].them
            drop += 1
        }
        if drop > 0 { recent.removeFirst(drop) }

        if them {
            if themRunStart == nil { themRunStart = t - dt }
        } else {
            themRunStart = nil
        }

        if me {
            if monologueStart == nil { monologueStart = t - dt }
            lastMeAt = t
        }

        if let start = monologueStart {
            longestMonologue = max(longestMonologue, lastMeAt - start)
            let tookOver = themRunStart.map { t - $0 >= floorTakeover } ?? false
            if !me && (tookOver || t - lastMeAt >= turnEndSilence) {
                monologueStart = nil
            }
        }
    }

    /// Length of your current turn, or 0 if you don't have the floor.
    public var currentMonologue: TimeInterval {
        guard let start = monologueStart else { return 0 }
        return (isMeSpeaking ? now : lastMeAt) - start
    }

    /// Your share of all speech so far (overlap counts for both sides).
    public var talkRatio: Double? {
        let total = meTotal + themTotal
        return total > 0 ? meTotal / total : nil
    }

    /// Your share of speech over the last `recentWindow` seconds.
    public var recentRatio: Double? {
        let total = recentMe + recentThem
        return total > 0 ? recentMe / total : nil
    }

    /// Total speech (both sides) in the recent window.
    public var recentSpeech: TimeInterval { recentMe + recentThem }
}
