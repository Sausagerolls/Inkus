import Foundation

/// Narrow keyword filter for acceptable-use compliance with Foundation Models.
/// We only screen *AI-generated output*, not the user's own writing — the user's
/// thoughts are theirs. If model output mentions a crisis term, downstream callers
/// substitute a neutral fallback and surface the crisis-resources card hint.
enum SafetyFilter {
    /// Crisis terms only. Kept narrow to minimise false positives.
    nonisolated private static let crisisTerms: [String] = [
        "suicide", "suicidal",
        "self-harm", "self harm", "selfharm",
        "kill myself", "end my life", "end it all",
        "cutting myself",
    ]

    /// True if the text contains any crisis term (case-insensitive).
    nonisolated static func containsCrisisLanguage(_ text: String) -> Bool {
        let haystack = text.lowercased()
        return crisisTerms.contains { haystack.contains($0) }
    }

    /// Sanitises a mood label to "neutral" if the model produced something concerning.
    nonisolated static func sanitisedMood(_ label: String) -> String {
        containsCrisisLanguage(label) ? "neutral" : label
    }
}
