import Foundation

/// Tiny JSON-on-disk handoff between the main app and the widget extension.
/// Lives inside the shared App Group container so both processes can read/write it.
///
/// Main app writes whenever today's DailyPrompt is created or refreshed.
/// Widget reads inside its TimelineProvider.
enum SharedPromptCache {
    static let appGroupID = "group.com.giantmushroom.Inkling"

    struct Snapshot: Codable, Equatable {
        var date: Date          // start of the day this prompt is for
        var promptText: String
        var followUps: [String]
        var sourceIsAI: Bool
        var accentHex: String   // current journal accent for tint
    }

    /// File URL inside the App Group container, or nil if the container isn't
    /// reachable (entitlement missing, etc.).
    static var fileURL: URL? {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        return dir.appendingPathComponent("today_prompt.json")
    }

    @discardableResult
    static func write(_ snapshot: Snapshot) -> Bool {
        guard let url = fileURL else { return false }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    static func read() -> Snapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return nil
        }
        return snap
    }
}
