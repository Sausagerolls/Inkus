import Foundation
import SwiftData

@Model
final class DailyPrompt {
    // CloudKit constraints: no .unique attributes; every property optional or with default.
    var id: UUID = UUID()
    var date: Date = Date.now           // start of the local day
    var promptText: String = ""
    var followUps: [String] = []        // 0–3 follow-up questions
    var generatedAt: Date = Date.now
    var wasUsed: Bool = false           // did user start an entry from it?
    var sourceIsAI: Bool = false        // false = fallback bank

    init(date: Date, promptText: String, followUps: [String], sourceIsAI: Bool) {
        self.id = UUID()
        self.date = date
        self.promptText = promptText
        self.followUps = followUps
        self.generatedAt = .now
        self.wasUsed = false
        self.sourceIsAI = sourceIsAI
    }
}
