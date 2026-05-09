import Foundation
import SwiftData

@Model
final class DailyPrompt {
    @Attribute(.unique) var id: UUID
    var date: Date              // start of the local day
    var promptText: String
    var followUps: [String]     // 0–3 follow-up questions
    var generatedAt: Date
    var wasUsed: Bool           // did user start an entry from it?
    var sourceIsAI: Bool        // false = fallback bank

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
