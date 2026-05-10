import Foundation

/// Curated, hand-written prompt bank for devices without Apple Intelligence,
/// or for any moment the on-device model is unavailable. Loaded once at first
/// access and held in memory for the life of the process.
enum FallbackPromptBank {
    private static let cache: [String] = loadFromBundle() ?? defaults

    private static let defaults: [String] = [
        "What's something you noticed today that almost slipped past you?",
        "What's one small thing that went well in the last 24 hours?",
        "What did you choose to ignore today?",
        "What's a word that fits how you're feeling right now?",
        "Who crossed your mind today, and why?",
    ]

    /// Returns a prompt that's stable for a given calendar date — every fallback
    /// user sees the same prompt on the same day, so the experience is repeatable.
    static func prompt(for date: Date) -> DailyPromptResponse {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        let prompt = cache[dayOfYear % cache.count]
        return DailyPromptResponse(prompt: prompt, followUps: [])
    }

    private static func loadFromBundle() -> [String]? {
        guard let url = Bundle.main.url(forResource: "FallbackPrompts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let prompts = try? JSONDecoder().decode([String].self, from: data),
              !prompts.isEmpty else {
            return nil
        }
        return prompts
    }
}
