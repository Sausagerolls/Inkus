import Foundation
import FoundationModels

/// On-device chat session, journal-aware.
///
/// One `JournalChatService` instance per active `ChatThread`. The wrapped
/// `LanguageModelSession` keeps multi-turn context internally, so we only
/// hand it the *new* user turn each time, not the full transcript.
///
/// Two surfaces:
///   • `.talk`   — Talk tab. Background context = recent entry digest
///                 (titles + clipped bodies, last ~14 days).
///   • `.editor` — Editor sheet. Background context = the current draft only.
///
/// The session itself enforces tone via `instructions`. Output is run
/// through `SafetyFilter` before being persisted; if it trips the filter
/// we substitute a neutral acknowledgement so we never echo crisis
/// language back to the writer.
actor JournalChatService {
    private let session: LanguageModelSession

    init(surface: ChatSurfaceKind, recentDigest: String) {
        // Anti-confabulation rules come FIRST — small models pattern-match
        // on whatever lives at the top of the system prompt. Topic priors
        // (mental health, mood, feelings) are deliberately not mentioned
        // here. Journals can be about anything: travel, recipes, work, code,
        // gardening, parenting. Don't hint at a topic the model should pick.
        let groundingRules = """
        You are a thinking partner for someone using a personal notes / \
        journal app. The journal can be about anything: travel, work, \
        cooking, gardening, code, family, books, ideas. Treat each user \
        as a blank slate until their writing tells you otherwise.

        ABSOLUTE RULES — these override everything else:
        1. NEVER claim the writer has been writing about a topic, theme, \
           or feeling unless that exact topic appears in the CONTEXT block \
           below. If the CONTEXT is empty, you have no information about \
           what they write about. Say so honestly and ask.
        2. NEVER assume the writer's emotional state, mental health, mood, \
           or wellbeing. Do not bring up feelings, stress, anxiety, \
           reflection, or self-care unless the writer raises it first.
        3. NEVER invent specific details — names, places, dates, events, \
           people, projects — that aren't in the CONTEXT block.
        4. If you genuinely don't know something, say "I don't know" or \
           "I don't have that in your notes." Asking a question is always \
           better than guessing.

        Tone: neutral, curious, practical. Short replies — usually two or \
        three sentences. One question at a time. Mirror the writer's \
        register: if they're casual, be casual; if they're technical, \
        be technical. Don't be performatively warm or therapeutic.
        """

        let surfaceRules: String = {
            switch surface {
            case .talk:
                return """
                The CONTEXT block below is a digest of the writer's recent \
                notes. Each line is one entry: [date · optional mood label] \
                followed by a snippet. Use it to ground your replies. \
                You may reference patterns you actually see in the snippets \
                ("you've mentioned the marathon training a few times"), but \
                never quote entries back verbatim and never name people. \
                If the digest is empty, do not fabricate themes — admit it \
                and ask what the writer wants to talk about.
                """
            case .editor:
                return """
                The CONTEXT block below is the writer's current draft. \
                Help only with this draft: get them unstuck, point out \
                what's vague, suggest a tighter phrasing for a sentence \
                they wrote. Stay strictly inside what's on the page.
                """
            }
        }()

        let context = recentDigest.isEmpty
            ? "--- CONTEXT ---\n(empty — the writer has no notes the assistant can see yet)\n--- END CONTEXT ---"
            : "--- CONTEXT ---\n\(recentDigest)\n--- END CONTEXT ---"

        // Safety guidance lives at the bottom and is phrased generically so
        // it doesn't seed the model with topic suggestions. We do NOT list
        // crisis topics here — the output-side SafetyFilter catches those.
        let safety = """
        For any sensitive topic the writer raises (health, legal, financial, \
        anything emotionally heavy): acknowledge briefly, do not give advice \
        or diagnoses, and suggest they speak with someone qualified.
        """

        self.session = LanguageModelSession(
            instructions: """
            \(groundingRules)

            \(surfaceRules)

            \(context)

            \(safety)
            """
        )
    }

    /// Sends one user turn and returns the model's reply, sanitised.
    /// Multi-turn context is held inside `session` itself.
    func reply(to userTurn: String) async throws -> String {
        let response = try await session.respond(to: userTurn)
        return Self.sanitised(response.content)
    }

    // MARK: - Helpers

    private static func sanitised(_ text: String) -> String {
        if SafetyFilter.containsCrisisLanguage(text) {
            return """
            That sounds heavy. I'm not the right place to sit with that — \
            please reach out to someone you trust, or a professional. \
            In the UK you can call Samaritans free on 116 123, any time.
            """
        }
        return text
    }
}

/// Builds the recent-entry digest passed to `.talk` chats.
///
/// The on-device model has a small context window. We pass the title +
/// first 280 chars of each entry from the last 14 days, capped at 20
/// entries, oldest-first.
enum ChatContextBuilder {
    static func recentDigest(from entries: [Entry], days: Int = 14, maxEntries: Int = 20) -> String {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let recent = entries
            .filter { $0.createdAt >= cutoff }
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(maxEntries)

        guard !recent.isEmpty else { return "" }

        return recent.map { entry -> String in
            let date = entry.createdAt.formatted(.dateTime.month(.abbreviated).day())
            let mood = entry.moodLabel.map { " · mood: \($0)" } ?? ""
            let body = entry.body.replacingOccurrences(of: "\n", with: " ")
            let snippet = body.count > 280 ? String(body.prefix(280)) + "…" : body
            return "[\(date)\(mood)] \(snippet)"
        }
        .joined(separator: "\n")
    }

    static func draftDigest(from entry: Entry) -> String {
        let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            return "The draft is currently empty."
        }
        let snippet = body.count > 1200 ? String(body.prefix(1200)) + "…" : body
        return "Current draft:\n\(snippet)"
    }
}
