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
        let baseRules = """
        You are a warm, attentive journaling companion. Your role is to help \
        the writer notice and explore what they're already thinking — not to \
        give advice, instructions, or solutions. Tone: curious, gentle, \
        unhurried. Mirror their language. Ask one question at a time. Keep \
        responses short — usually two or three sentences, occasionally a \
        single sentence.

        Hard rules:
        • Never diagnose, prescribe, or recommend medical / legal / financial action.
        • Never produce content about self-harm, suicide, eating disorders, or \
          substance abuse. If the writer raises any of these, gently acknowledge \
          and suggest speaking to someone they trust or a professional. Do not elaborate.
        • Do not pretend to remember things outside the current conversation \
          and the context block below.
        • Do not invent details about the writer's life that aren't in the context.
        """

        let surfaceRules: String = {
            switch surface {
            case .talk:
                return """
                You have access to a digest of the writer's recent journal \
                entries below. You may reference broad patterns ("you've \
                been writing a lot about X lately"), but never quote entries \
                back verbatim and never name people who appear in them.
                """
            case .editor:
                return """
                You have access to the writer's current draft below. Help \
                them get unstuck, notice what they're avoiding, or rephrase \
                a passage more honestly. Stay grounded in what they've \
                actually written.
                """
            }
        }()

        let context = recentDigest.isEmpty
            ? "No prior writing is available for context."
            : "--- CONTEXT ---\n\(recentDigest)\n--- END CONTEXT ---"

        self.session = LanguageModelSession(
            instructions: """
            \(baseRules)

            \(surfaceRules)

            \(context)
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
