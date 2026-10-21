import SwiftUI
import YapCore

struct MenuBarLabel: View {
    @ObservedObject var engine: YapEngine

    var body: some View {
        if !engine.isLive {
            Image(systemName: "waveform")
        } else if engine.snapshot.monologue >= 20 {
            Text("🗣 \(formatDuration(engine.snapshot.monologue))")
        } else if let ratio = engine.snapshot.ratio {
            Text("\(ratioEmoji(ratio)) \(Int(ratio * 100))%")
        } else {
            Text("● yap")
        }
    }

    private func ratioEmoji(_ ratio: Double) -> String {
        ratio > 0.65 ? "🔴" : ratio > 0.5 ? "🟠" : "🟢"
    }
}

struct MenuView: View {
    @EnvironmentObject var engine: YapEngine
    @State private var showSettings = false

    private let meColor = Color.orange
    private let themColor = Color.teal

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let error = engine.error {
                warning(error)
            }
            if engine.isLive {
                live
            } else {
                idle
            }
            Divider()
            history
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 330)
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text("yap")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            if engine.isLive {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text(formatDuration(engine.snapshot.elapsed))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(engine.isLive ? "Stop" : "Start") { engine.toggle() }
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let app = engine.callApp {
                Label("\(app) is using the mic", systemImage: "phone.fill")
                    .font(.system(size: 13))
            } else {
                Text(engine.autoStart
                     ? "Waiting for a call. Yap starts by itself when Zoom, Meet, Teams or another app opens your mic."
                     : "Press Start when your call begins.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 14) {
            ratioBar
            VStack(spacing: 6) {
                meterRow("You", level: engine.snapshot.meLevel, speaking: engine.snapshot.meSpeaking, color: meColor)
                meterRow("Them", level: engine.snapshot.themLevel, speaking: engine.snapshot.themSpeaking, color: themColor)
            }
            if !engine.hearsOtherSide {
                warning("Yap can't hear the other side, so it only tracks how long you talk. Allow Screen & System Audio Recording.",
                        action: ("Open Settings", engine.openScreenRecordingSettings))
            }
            turnCard
            statsGrid
        }
    }

    private var ratioBar: some View {
        let ratio = engine.snapshot.ratio ?? 0.5
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("You \(engine.snapshot.ratio.map { "\(Int($0 * 100))%" } ?? "–")")
                    .foregroundStyle(meColor)
                Spacer()
                Text("Them \(engine.snapshot.ratio.map { "\(100 - Int($0 * 100))%" } ?? "–")")
                    .foregroundStyle(themColor)
            }
            .font(.system(size: 13, weight: .semibold))
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4).fill(meColor)
                        .frame(width: max(4, (geo.size.width - 2) * ratio))
                    RoundedRectangle(cornerRadius: 4).fill(themColor)
                }
            }
            .frame(height: 10)
            .animation(.easeOut(duration: 0.4), value: ratio)
            if let recent = engine.snapshot.recentRatio {
                Text("Last 5 min: you \(Int(recent * 100))%")
                    .font(.system(size: 11))
                    .foregroundStyle(recent > 0.65 ? .red : .secondary)
            }
        }
    }

    private func meterRow(_ name: String, level: Double, speaking: Bool, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(speaking ? color : Color.secondary.opacity(0.25))
                .frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 12))
                .frame(width: 40, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color.opacity(speaking ? 1 : 0.4))
                        .frame(width: geo.size.width * level)
                }
            }
            .frame(height: 5)
            .animation(.linear(duration: 0.1), value: level)
        }
    }

    private var turnCard: some View {
        let mono = engine.snapshot.monologue
        let progress = min(Double(mono) / max(engine.askAfter, 1), 1)
        let color: Color = Double(mono) >= engine.askAfter ? .red : Double(mono) >= engine.breatheAfter ? .orange : .green
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mono > 0 ? "Your current turn" : "You're listening")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(mono > 0 ? formatDuration(mono) : "👂")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(mono > 0 ? color : .secondary)
            }
            ProgressView(value: progress)
                .tint(color)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
    }

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                stat("You talked", formatDuration(engine.snapshot.me))
                stat("They talked", formatDuration(engine.snapshot.them))
            }
            GridRow {
                stat("Longest turn", formatDuration(engine.snapshot.longestMonologue))
                stat("Nudges", "\(engine.snapshot.nudges)")
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .medium, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent calls")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if engine.sessions.isEmpty {
                Text("Nothing yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            ForEach(engine.sessions.prefix(5)) { s in
                HStack(spacing: 8) {
                    Text(s.start, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .frame(width: 90, alignment: .leading)
                    Text(s.app ?? "Call")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatDuration(Int(s.duration)))
                        .foregroundStyle(.secondary)
                    if let r = s.ratio {
                        Text("\(Int(r * 100))%")
                            .fontWeight(.semibold)
                            .foregroundStyle(r > 0.65 ? .red : r > 0.5 ? .orange : .green)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup("Settings", isExpanded: $showSettings) {
                VStack(alignment: .leading, spacing: 8) {
                    Stepper("Breathe nudge after \(Int(engine.breatheAfter))s",
                            value: $engine.breatheAfter, in: 15...300, step: 15)
                    Stepper("Ask-a-question after \(Int(engine.askAfter))s",
                            value: $engine.askAfter, in: 30...600, step: 15)
                    Toggle("Start automatically on calls", isOn: $engine.autoStart)
                    Toggle("Echo cancellation (no headphones)", isOn: $engine.echoCancellation)
                        .help("Takes effect on the next call")
                }
                .font(.system(size: 12))
                .padding(.top, 6)
            }
            .font(.system(size: 12))
            HStack {
                Spacer()
                Button("Quit Yap") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func warning(_ text: String, action: (String, () -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.0, action: action.1).controlSize(.small)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.15)))
    }
}
