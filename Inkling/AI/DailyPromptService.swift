import Foundation
import SwiftData

/// Owns the lifecycle of today's `DailyPrompt`:
///   - if one exists for today, return it
///   - otherwise generate via PromptGenerator (or fall back to the bundled bank)
///   - persist the result so we don't regenerate within the same day
///
/// Pull-to-refresh in EntryListView calls `regenerate(for:)` which deletes
/// today's row before recomputing.
@MainActor
struct DailyPromptService {
    let context: ModelContext

    func todaysPrompt() async -> DailyPrompt {
        if let existing = fetchToday() { return existing }
        return await generateAndStore(replacingExisting: false)
    }

    func regenerate() async -> DailyPrompt {
        return await generateAndStore(replacingExisting: true)
    }

    // MARK: Internals

    private func startOfToday() -> Date {
        Calendar.current.startOfDay(for: .now)
    }

    private func fetchToday() -> DailyPrompt? {
        let day = startOfToday()
        var descriptor = FetchDescriptor<DailyPrompt>(
            predicate: #Predicate { $0.date == day }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func recentMoodLabels() -> [String] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        var descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.createdAt >= cutoff }
        )
        descriptor.fetchLimit = 50
        let entries = (try? context.fetch(descriptor)) ?? []
        let labels = entries.compactMap(\.moodLabel)
        return Array(Set(labels))
    }

    private func recentThemes() -> [String] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        var descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.createdAt >= cutoff }
        )
        descriptor.fetchLimit = 50
        let entries = (try? context.fetch(descriptor)) ?? []
        var counts: [String: Int] = [:]
        for tag in entries.flatMap(\.tags) {
            counts[tag, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(5).map(\.key)
    }

    private func generateAndStore(replacingExisting: Bool) async -> DailyPrompt {
        let day = startOfToday()
        if replacingExisting, let existing = fetchToday() {
            context.delete(existing)
        }

        let dateString = Date.now.formatted(.dateTime.weekday(.wide).month().day())
        let promptCtx = PromptContext(
            dateString: dateString,
            recentMoodLabels: recentMoodLabels(),
            recentThemes: recentThemes(),
            userName: nil
        )

        let response: DailyPromptResponse
        let sourceIsAI: Bool
        if AIAvailability.isAvailable {
            do {
                response = try await PromptGenerator().generateDailyPrompt(context: promptCtx)
                sourceIsAI = true
            } catch {
                response = FallbackPromptBank.prompt(for: day)
                sourceIsAI = false
            }
        } else {
            response = FallbackPromptBank.prompt(for: day)
            sourceIsAI = false
        }

        let prompt = DailyPrompt(
            date: day,
            promptText: response.prompt,
            followUps: response.followUps,
            sourceIsAI: sourceIsAI
        )
        context.insert(prompt)
        try? context.save()
        return prompt
    }
}
