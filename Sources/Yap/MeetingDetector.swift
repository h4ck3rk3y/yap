import AppKit
import CoreAudio

/// Finds other apps currently recording from a microphone — the signal that
/// a call has started (Zoom, Meet in a browser, Teams, Slack huddles, Granola…).
enum MeetingDetector {
    /// Display names of other processes that are recording audio right now.
    static func appsUsingMic() -> [String] {
        var names: [String] = []
        for id in processObjects() {
            var pid: pid_t = 0
            var running: UInt32 = 0
            guard read(id, kAudioProcessPropertyPID, &pid), pid != getpid(),
                  read(id, kAudioProcessPropertyIsRunningInput, &running), running != 0 else { continue }

            var cfBundle: Unmanaged<CFString>?
            _ = read(id, kAudioProcessPropertyBundleID, &cfBundle)
            let bundleID = cfBundle?.takeRetainedValue() as String? ?? ""
            guard !isIgnored(bundleID) else { continue }

            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? bundleID
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// System daemons (Siri, dictation…) touch the mic without being a call.
    /// Safari's audio goes through WebKit processes, and FaceTime is a call.
    private static func isIgnored(_ bundleID: String) -> Bool {
        if bundleID.isEmpty { return true }
        guard bundleID.hasPrefix("com.apple.") else { return false }
        return !(bundleID.contains("WebKit") || bundleID.contains("FaceTime") || bundleID.contains("Safari"))
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func read<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) == noErr
        }
    }
}
