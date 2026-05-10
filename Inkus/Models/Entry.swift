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

    // Legacy on-disk attachment filenames. Kept for one-time migration into
    // the new Attachment @Model rows; new code should read `attachments`.
    var photoFilenames: [String] = []
    var audioFilenames: [String] = []

    /// CloudKit-syncable attachments. Cascade-deleted with the entry.
    @Relationship(deleteRule: .cascade, inverse: \Attachment.entry)
    var attachments: [Attachment]? = []

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
