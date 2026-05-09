import Foundation
import FoundationModels

@Generable
struct MoodSuggestion {
    @Guide(description: "A single mood label, lowercase, one word. Pick from: calm, content, joyful, energised, focused, anxious, sad, frustrated, tired, restless, grateful, hopeful, conflicted, lonely, neutral.")
    let mood: String

    @Guide(description: "An emoji that matches the mood.")
    let emoji: String

    @Guide(description: "Up to 3 short tags (1–2 words each) describing the themes of the entry. Lowercase. No hashtags.")
    let tags: [String]
}

actor MoodSuggester {
    func suggest(for body: String) async throws -> MoodSuggestion {
        let session = LanguageModelSession(
            instructions: """
            You read a short journal entry and infer the writer's mood and 1–3 \
            theme tags. Be conservative. If uncertain, choose 'neutral'.
            """
        )
        let response = try await session.respond(
            to: "Entry:\n\(body.prefix(2000))",
            generating: MoodSuggestion.self
        )
        let raw = response.content
        let safeMood = SafetyFilter.sanitisedMood(raw.mood)
        return MoodSuggestion(
            mood: safeMood,
            emoji: safeMood == "neutral" ? "😐" : raw.emoji,
            tags: raw.tags
        )
    }
}
