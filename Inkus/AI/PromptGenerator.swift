import Foundation
import FoundationModels

@Generable
struct DailyPromptResponse {
    @Guide(description: "An open-ended journaling prompt, 1 sentence, ≤ 25 words, gentle and curious in tone. No commands. Avoid words like 'must', 'should', 'need to'.")
    let prompt: String

    @Guide(description: "Two short follow-up questions that invite deeper reflection. Each ≤ 15 words. Phrased as questions ending with '?'.")
    let followUps: [String]
}

struct PromptContext {
    let dateString: String          // "Saturday, May 9"
    let recentMoodLabels: [String]  // last 7 days, deduped
    let recentThemes: [String]      // top 5 from last 7 days
    let userName: String?           // optional
}

actor PromptGenerator {
    func generateDailyPrompt(context: PromptContext) async throws -> DailyPromptResponse {
        let session = LanguageModelSession(
            instructions: """
            You are a gentle journaling companion. Your role is to offer a single \
            short prompt that helps the writer notice or explore something in their day. \
            Tone: warm, curious, never instructive. Avoid clichés. Never reference \
            specific names or events from the writer's recent entries — keep prompts \
            general but resonant. Output must be SAFE and SUPPORTIVE; do not generate \
            content about self-harm, eating disorders, or substance abuse.
            """
        )

        let recentSignal: String = {
            var lines: [String] = []
            if !context.recentThemes.isEmpty {
                lines.append("Recent themes the writer has been exploring: \(context.recentThemes.joined(separator: ", ")).")
            }
            if !context.recentMoodLabels.isEmpty {
                lines.append("Recent mood notes: \(context.recentMoodLabels.joined(separator: ", ")).")
            }
            return lines.joined(separator: " ")
        }()

        let response = try await session.respond(
            to: """
            Today is \(context.dateString). \(recentSignal)

            Generate one prompt and two follow-up questions for today.
            """,
            generating: DailyPromptResponse.self
        )

        return response.content
    }
}
