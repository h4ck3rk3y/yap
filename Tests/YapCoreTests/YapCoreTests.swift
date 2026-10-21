import XCTest
@testable import YapCore

final class VoiceDetectorTests: XCTestCase {
    func testDetectsSpeechAboveFloorAndHangsOver() {
        var vad = VoiceDetector(hangover: 0.3)
        var t = 0.0
        for _ in 0..<20 { t += 0.1; XCTAssertFalse(vad.process(levelDB: -70, at: t)) }
        t += 0.1; XCTAssertTrue(vad.process(levelDB: -25, at: t))
        t += 0.1; XCTAssertTrue(vad.process(levelDB: -70, at: t), "hangover keeps voice on")
        t += 0.3; XCTAssertFalse(vad.process(levelDB: -70, at: t))
    }

    func testIgnoresQuietLevelsInSilentRoom() {
        var vad = VoiceDetector(minLevelDB: -48)
        XCTAssertFalse(vad.process(levelDB: -100, at: 0.1))
        XCTAssertFalse(vad.process(levelDB: -60, at: 0.2), "above floor but below absolute minimum")
    }

    func testExtraMarginRejectsBleed() {
        var vad = VoiceDetector(hangover: 0)
        for i in 0..<10 { _ = vad.process(levelDB: -70, at: Double(i) * 0.1) }
        XCTAssertFalse(vad.process(levelDB: -45, at: 1.1, extraMarginDB: 15))
        XCTAssertTrue(vad.process(levelDB: -25, at: 1.2, extraMarginDB: 15))
    }

    func testLongSpeechWithGapsKeepsFloorLow() {
        var vad = VoiceDetector()
        var t = 0.0
        for i in 0..<600 { // 60s of speech with a breath every second
            t += 0.1
            let level: Float = i % 10 == 0 ? -65 : -25
            _ = vad.process(levelDB: level, at: t)
        }
        XCTAssertLessThan(vad.noiseFloorDB, -60)
        XCTAssertTrue(vad.process(levelDB: -25, at: t + 0.1))
    }
}

final class ConversationTrackerTests: XCTestCase {
    private func run(_ c: inout ConversationTracker, _ t: inout Double, seconds: Double, me: Bool, them: Bool) {
        for _ in 0..<Int((seconds * 10).rounded()) {
            t += 0.1
            c.update(me: me, them: them, at: t, dt: 0.1)
        }
    }

    func testTotalsAndRatio() {
        var c = ConversationTracker(), t = 0.0
        run(&c, &t, seconds: 30, me: true, them: false)
        run(&c, &t, seconds: 10, me: false, them: true)
        XCTAssertEqual(c.meTotal, 30, accuracy: 0.01)
        XCTAssertEqual(c.themTotal, 10, accuracy: 0.01)
        XCTAssertEqual(c.talkRatio!, 0.75, accuracy: 0.001)
    }

    func testBackchannelDoesNotEndMonologue() {
        var c = ConversationTracker(), t = 0.0
        run(&c, &t, seconds: 20, me: true, them: false)
        run(&c, &t, seconds: 0.5, me: false, them: true) // "mhm"
        run(&c, &t, seconds: 20, me: true, them: false)
        XCTAssertEqual(c.currentMonologue, 40.5, accuracy: 0.01)
    }

    func testTakeoverEndsMonologue() {
        var c = ConversationTracker(), t = 0.0
        run(&c, &t, seconds: 20, me: true, them: false)
        run(&c, &t, seconds: 1.2, me: false, them: true)
        XCTAssertEqual(c.currentMonologue, 0)
        XCTAssertEqual(c.longestMonologue, 20, accuracy: 0.01)
    }

    func testTalkingOverThemKeepsMonologue() {
        var c = ConversationTracker(), t = 0.0
        run(&c, &t, seconds: 10, me: true, them: false)
        run(&c, &t, seconds: 3, me: true, them: true)
        XCTAssertEqual(c.currentMonologue, 13, accuracy: 0.01)
    }

    func testLongPauseEndsMonologue() {
        var c = ConversationTracker(), t = 0.0
        run(&c, &t, seconds: 10, me: true, them: false)
        run(&c, &t, seconds: 2, me: false, them: false)
        XCTAssertGreaterThan(c.currentMonologue, 0, "short pause keeps the turn")
        run(&c, &t, seconds: 1.5, me: false, them: false)
        XCTAssertEqual(c.currentMonologue, 0)
    }

    func testRecentWindowForgetsOldSpeech() {
        var c = ConversationTracker(recentWindow: 60), t = 0.0
        run(&c, &t, seconds: 60, me: true, them: false)
        run(&c, &t, seconds: 60, me: false, them: true)
        XCTAssertEqual(c.recentRatio!, 0, accuracy: 0.01)
        XCTAssertEqual(c.talkRatio!, 0.5, accuracy: 0.01)
    }
}

final class NudgePolicyTests: XCTestCase {
    func testEscalatesThenClears() {
        var c = ConversationTracker(), p = NudgePolicy(breatheAfter: 60, askAfter: 90), t = 0.0
        var seen: [NudgeKind?] = []
        for _ in 0..<950 {
            t += 0.1
            c.update(me: true, them: false, at: t, dt: 0.1)
            let n = p.evaluate(c, at: t)
            if seen.last != .some(n) { seen.append(n) }
        }
        XCTAssertEqual(seen, [nil, .breathe, .askQuestion])
        for _ in 0..<15 {
            t += 0.1
            c.update(me: false, them: true, at: t, dt: 0.1)
            _ = p.evaluate(c, at: t)
        }
        XCTAssertNil(p.evaluate(c, at: t))
        XCTAssertEqual(p.nudgeCount, 2)
    }

    func testDominatingFiresOnceThenCoolsDown() {
        var c = ConversationTracker(turnEndSilence: 0.5), p = NudgePolicy(), t = 0.0
        var fired = 0, last: NudgeKind?
        // Short turns (no monologue nudges) but 80% of the airtime, for 6 minutes.
        for i in 0..<3600 {
            t += 0.1
            let me = i % 100 < 40, them = i % 100 >= 40 && i % 100 < 50
            c.update(me: me, them: them, at: t, dt: 0.1)
            let n = p.evaluate(c, at: t)
            if case .dominating = n, last == nil { fired += 1 }
            last = n
        }
        XCTAssertEqual(fired, 1)
    }
}
