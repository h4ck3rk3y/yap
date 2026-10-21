import Foundation

struct SessionRecord: Codable, Identifiable {
    var id = UUID()
    var start: Date
    var duration: TimeInterval
    var me: TimeInterval
    var them: TimeInterval
    var longestMonologue: TimeInterval
    var nudges: Int
    var app: String?

    var ratio: Double? { me + them > 0 ? me / (me + them) : nil }
}

/// Past meetings, kept as JSON in ~/Library/Application Support/Yap.
final class SessionStore {
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Yap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("sessions.json")
    }

    func load() -> [SessionRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SessionRecord].self, from: data)) ?? []
    }

    func save(_ sessions: [SessionRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        try? encoder.encode(sessions).write(to: url, options: .atomic)
    }
}
