import Foundation
import SwiftData

@Model
final class Entry {
    // CloudKit constraints: no .unique attributes; every property optional or with default.
    var id: UUID = UUID()
    var title: String?
    var body: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Mood
    var moodEmoji: String?
    var moodLabel: String?       // e.g. "calm", "anxious", "energised"
    var moodConfidence: Double?  // 0.0–1.0; >0 means AI-suggested

    // Tags (free-form; lowercase strings)
    var tags: [String] = []

    // Context captured at write time
    var weatherSummary: String?  // "sunny, 18°C"
    var locationName: String?    // city or place name only — never coords stored

    // Attachments — filename references; binaries stay device-local for v1.0
    // (sync of binary attachments is a v1.1 feature per Phase 5.4 decision).
    var photoFilenames: [String] = []
    var audioFilenames: [String] = []

    // Source of the prompt that generated this entry, if any
    var sourcePromptID: UUID?

    var journal: Journal?

    init(body: String = "", journal: Journal? = nil) {
        self.id = UUID()
        self.body = body
        self.createdAt = .now
        self.updatedAt = .now
        self.tags = []
        self.photoFilenames = []
        self.audioFilenames = []
        self.journal = journal
    }
}
