import Foundation

public enum NudgeKind: Equatable {
    /// You've held the floor for a while: take a breath.
    case breathe
    /// You've held the floor for a long time: stop and ask them something.
    case askQuestion
    /// You've had most of the airtime recently.
    case dominating(ratio: Double)
}

/// Decides which nudge, if any, should be on screen right now.
public struct NudgePolicy {
    public var breatheAfter: TimeInterval
    public var askAfter: TimeInterval
    public var dominatingRatio: Double
    /// Minimum speech (both sides) in the recent window before judging the ratio.
    public var dominatingMinSpeech: TimeInterval
    public var dominatingCooldown: TimeInterval
    public var dominatingDisplay: TimeInterval

    /// Number of nudges shown (each escalation counts).
    public private(set) var nudgeCount = 0
    private var current: NudgeKind?
    private var lastDominatingAt: TimeInterval = -.greatestFiniteMagnitude
    private var dominatingShown: NudgeKind?

    public init(breatheAfter: TimeInterval = 60, askAfter: TimeInterval = 90, dominatingRatio: Double = 0.7,
                dominatingMinSpeech: TimeInterval = 120, dominatingCooldown: TimeInterval = 300,
                dominatingDisplay: TimeInterval = 8) {
        self.breatheAfter = breatheAfter
        self.askAfter = askAfter
        self.dominatingRatio = dominatingRatio
        self.dominatingMinSpeech = dominatingMinSpeech
        self.dominatingCooldown = dominatingCooldown
        self.dominatingDisplay = dominatingDisplay
    }

    public mutating func evaluate(_ convo: ConversationTracker, at t: TimeInterval) -> NudgeKind? {
        let mono = convo.currentMonologue
        var next: NudgeKind?
        if mono >= askAfter {
            next = .askQuestion
        } else if mono >= breatheAfter {
            next = .breathe
        } else if t - lastDominatingAt < dominatingDisplay {
            next = dominatingShown
        } else if t - lastDominatingAt >= dominatingCooldown,
                  convo.isMeSpeaking,
                  convo.recentSpeech >= dominatingMinSpeech,
                  let ratio = convo.recentRatio, ratio >= dominatingRatio {
            lastDominatingAt = t
            dominatingShown = .dominating(ratio: ratio)
            next = dominatingShown
        }
        if let next, next != current { nudgeCount += 1 }
        current = next
        return next
    }
}
