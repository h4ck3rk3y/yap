import AVFoundation
import AppKit
import YapCore

/// What the UI shows, rounded so SwiftUI only redraws when something visible changes.
struct LiveSnapshot: Equatable {
    var elapsed = 0
    var me = 0
    var them = 0
    var ratio: Double?
    var recentRatio: Double?
    var monologue = 0
    var longestMonologue = 0
    var nudges = 0
    var meLevel = 0.0
    var themLevel = 0.0
    var meSpeaking = false
    var themSpeaking = false
}

@MainActor
final class YapEngine: ObservableObject {
    @Published private(set) var isLive = false
    @Published private(set) var snapshot = LiveSnapshot()
    @Published private(set) var nudge: NudgeKind?
    @Published private(set) var callApp: String?
    @Published private(set) var hearsOtherSide = true
    @Published private(set) var error: String?
    @Published private(set) var sessions: [SessionRecord] = []

    @Published var breatheAfter: Double { didSet { save(breatheAfter, "breatheAfter"); policy.breatheAfter = breatheAfter } }
    @Published var askAfter: Double { didSet { save(askAfter, "askAfter"); policy.askAfter = askAfter } }
    @Published var autoStart: Bool { didSet { save(autoStart, "autoStart") } }
    @Published var echoCancellation: Bool { didSet { save(echoCancellation, "echoCancellation") } }

    private let mic = MicCapture()
    private let system = SystemAudioCapture()
    private let store = SessionStore()
    private lazy var overlay = NudgeOverlay(engine: self)

    private var meVAD = VoiceDetector(minLevelDB: -48)
    private var themVAD = VoiceDetector(minLevelDB: -55)
    private var convo = ConversationTracker()
    private var policy = NudgePolicy()

    private var tickTimer: Timer?
    private var pollTimer: Timer?
    private var isStarting = false
    private var startedAt = Date()
    private var startUptime: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    private var sessionAutoStarted = false
    private var sessionApp: String?
    private var dismissed = false
    private var dismissedMonologue: TimeInterval?

    // Meeting auto-detection state.
    private var micBusySince: TimeInterval?
    private var micFreeSince: TimeInterval?
    private var suppressAutoStart = false

    /// Extra dB the mic must clear while the other side is talking, so their
    /// voice leaking from laptop speakers into the mic isn't counted as you.
    private let bleedMarginDB: Float = 15

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["breatheAfter": 60.0, "askAfter": 90.0, "autoStart": true, "echoCancellation": false])
        breatheAfter = d.double(forKey: "breatheAfter")
        askAfter = d.double(forKey: "askAfter")
        autoStart = d.bool(forKey: "autoStart")
        echoCancellation = d.bool(forKey: "echoCancellation")
        sessions = store.load()

        let poll = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollMeeting() }
        }
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll
    }

    // MARK: - Session lifecycle

    func toggle() {
        if isLive {
            stop()
            if callApp != nil { suppressAutoStart = true }
        } else {
            start(auto: false)
        }
    }

    func start(auto: Bool) {
        guard !isLive, !isStarting else { return }
        isStarting = true
        Task {
            defer { isStarting = false }
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                error = "Microphone access is off. Enable Yap in System Settings → Privacy & Security → Microphone."
                return
            }
            do {
                try mic.start(voiceProcessing: echoCancellation)
            } catch {
                self.error = "Couldn't open the microphone: \(error.localizedDescription)"
                return
            }
            do {
                try await system.start()
                hearsOtherSide = true
                self.error = nil
            } catch {
                // Still useful without it: monologue nudges work from the mic alone.
                hearsOtherSide = false
                self.error = nil
            }

            meVAD.reset()
            themVAD.reset()
            convo = ConversationTracker()
            policy = NudgePolicy(breatheAfter: breatheAfter, askAfter: askAfter)
            dismissed = false
            nudge = nil
            snapshot = LiveSnapshot()
            startedAt = Date()
            startUptime = ProcessInfo.processInfo.systemUptime
            lastTick = startUptime
            sessionAutoStarted = auto
            sessionApp = callApp
            isLive = true

            let tick = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(tick, forMode: .common)
            tickTimer = tick
        }
    }

    func stop() {
        guard isLive else { return }
        tickTimer?.invalidate()
        tickTimer = nil
        mic.stop()
        system.stop()
        isLive = false
        nudge = nil
        overlay.hide()

        let duration = Date().timeIntervalSince(startedAt)
        if duration >= 30 {
            let record = SessionRecord(
                start: startedAt, duration: duration, me: convo.meTotal, them: convo.themTotal,
                longestMonologue: convo.longestMonologue, nudges: policy.nudgeCount, app: sessionApp)
            sessions.insert(record, at: 0)
            sessions = Array(sessions.prefix(200))
            store.save(sessions)
        }
    }

    /// Hide the current nudge until this turn ends.
    func dismissNudge() {
        dismissed = true
        dismissedMonologue = convo.monologueStart
        nudge = nil
        overlay.hide()
    }

    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    // MARK: - Live loop

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - lastTick, 0.5)
        lastTick = now
        let t = now - startUptime

        let themDB = system.levels.drainDB()
        let meDB = mic.levels.drainDB()
        let them = hearsOtherSide && themVAD.process(levelDB: themDB, at: t)
        let me = meVAD.process(levelDB: meDB, at: t,
                               extraMarginDB: them && !echoCancellation ? bleedMarginDB : 0)
        convo.update(me: me, them: them, at: t, dt: dt)

        var next = policy.evaluate(convo, at: t)
        if dismissed {
            if convo.monologueStart == dismissedMonologue {
                next = nil
            } else {
                dismissed = false
            }
        }
        if next != nudge {
            nudge = next
            if next != nil { overlay.show() } else { overlay.hide() }
        }

        let s = LiveSnapshot(
            elapsed: Int(t), me: Int(convo.meTotal), them: Int(convo.themTotal),
            ratio: convo.talkRatio.map { ($0 * 100).rounded() / 100 },
            recentRatio: convo.recentRatio.map { ($0 * 100).rounded() / 100 },
            monologue: Int(convo.currentMonologue), longestMonologue: Int(convo.longestMonologue),
            nudges: policy.nudgeCount,
            meLevel: meter(meDB), themLevel: meter(themDB),
            meSpeaking: me, themSpeaking: them)
        if s != snapshot { snapshot = s }
    }

    /// Map dBFS to a 0…1 meter value, quantised to limit redraws.
    private func meter(_ db: Float) -> Double {
        let v = Double((db + 60) / 50).clamped(to: 0...1)
        return (v * 20).rounded() / 20
    }

    // MARK: - Meeting detection

    private func pollMeeting() {
        let apps = MeetingDetector.appsUsingMic()
        let now = ProcessInfo.processInfo.systemUptime
        if apps.isEmpty {
            micBusySince = nil
            if micFreeSince == nil { micFreeSince = now }
            suppressAutoStart = false
        } else {
            micFreeSince = nil
            if micBusySince == nil { micBusySince = now }
        }
        let app = apps.first
        if app != callApp { callApp = app }
        if isLive, sessionApp == nil, let app { sessionApp = app }

        // A few seconds of sustained mic use means a call, not a quick dictation.
        if !isLive, autoStart, !suppressAutoStart, let since = micBusySince, now - since >= 4 {
            start(auto: true)
        }
        if isLive, sessionAutoStarted, let since = micFreeSince, now - since >= 12 {
            stop()
        }
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

func formatDuration(_ seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
