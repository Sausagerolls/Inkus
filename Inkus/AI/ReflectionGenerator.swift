import Foundation
import FoundationModels

@Generable
struct WeeklyReflectionResponse {
    @Guide(description: "A 3-paragraph reflective summary in second person ('You'). Warm, observational, not advice-giving. ~180 words total.")
    let summary: String

    @Guide(description: "Top 3 themes the writer touched on this week. Short noun phrases. Lowercase.")
    let themes: [String]

    @Guide(description: "One sentence describing the arc of mood across the week.")
    let moodArc: String
}

actor ReflectionGenerator {
    func generate(entries: [Entry]) async throws -> WeeklyReflectionResponse {
        let bullets = entries
            .sorted { $0.createdAt < $1.createdAt }
            .map { entry -> String in
                let date = entry.createdAt.formatted(.dateTime.weekday(.wide))
                let mood = entry.moodLabel.map { " (\($0))" } ?? ""
                return "- \(date)\(mood): \(entry.body.prefix(400))"
            }
            .joined(separator: "\n")

        let session = LanguageModelSession(
            instructions: """
            You are reflecting on a week of someone's journal entries. \
            Write a warm 3-paragraph summary that surfaces themes and patterns \
            the writer might not have noticed themselves. Do not give advice. \
            Do not be sycophantic. Use second person.
            """
        )

        let response = try await session.respond(
            to: "Here are the writer's entries for this week:\n\n\(bullets)",
            generating: WeeklyReflectionResponse.self
        )

        let raw = response.content
        // Safety: if the model produced crisis language in summary, clamp to a neutral
        // placeholder summary so we never surface concerning text back to the writer.
        if SafetyFilter.containsCrisisLanguage(raw.summary) {
            return WeeklyReflectionResponse(
                summary: "Your week is here. We've left the reflection blank this time so you can write what feels right.",
                themes: [],
                moodArc: "A quiet week."
            )
        }
        return raw
    }
}
