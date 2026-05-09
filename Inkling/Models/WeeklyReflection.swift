import Foundation
import SwiftData

@Model
final class WeeklyReflection {
    @Attribute(.unique) var id: UUID
    var weekStartDate: Date     // ISO Monday 00:00 local
    var summary: String         // 3–4 paragraph narrative
    var themes: [String]        // top themes: ["work stress", "running", "sleep"]
    var moodArcDescription: String
    var generatedAt: Date

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
