import Foundation
import SwiftData

@Model
final class WeeklyReflection {
    // CloudKit constraints: no .unique attributes; every property optional or with default.
    var id: UUID = UUID()
    var weekStartDate: Date = Date.now  // ISO Monday 00:00 local
    var summary: String = ""             // 3–4 paragraph narrative
    var themes: [String] = []            // top themes
    var moodArcDescription: String = ""
    var generatedAt: Date = Date.now

    var journal: Journal?

    init(weekStartDate: Date, summary: String, themes: [String], moodArc: String) {
        self.id = UUID()
        self.weekStartDate = weekStartDate
        self.summary = summary
        self.themes = themes
        self.moodArcDescription = moodArc
        self.generatedAt = .now
    }
}
