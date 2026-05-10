import Foundation
import SwiftData

/// Orchestrates "should we offer a weekly reflection?" and persistence of results.
@MainActor
struct ReflectionService {
    let context: ModelContext

    /// ISO calendar with week starting Monday.
    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        return cal
    }()

    /// Returns the start (Monday 00:00 local) of the previous ISO week.
    static func previousWeekStart(from date: Date = .now) -> Date {
        let cal = calendar
        let thisWeekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
        return cal.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
    }

    static func previousWeekRange(from date: Date = .now) -> (start: Date, end: Date) {
        let start = previousWeekStart(from: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return (start, end)
    }

    /// True when we should offer to generate the reflection for the previous week:
    /// today is Sunday-or-later in the current week, no reflection exists for last week,
    /// and at least 3 entries fall in last week.
    func shouldOfferPreviousWeekReflection(for journal: Journal? = nil) -> Bool {
        let (start, end) = Self.previousWeekRange()
        if existingReflection(for: start, journal: journal) != nil { return false }
        return entryCount(in: start..<end, journal: journal) >= 3
    }

    func existingReflection(for weekStart: Date, journal: Journal? = nil) -> WeeklyReflection? {
        var descriptor = FetchDescriptor<WeeklyReflection>(
            predicate: #Predicate { $0.weekStartDate == weekStart }
        )
        descriptor.fetchLimit = 5
        let candidates = (try? context.fetch(descriptor)) ?? []
        if let target = journal {
            return candidates.first { $0.journal?.id == target.id }
        }
        return candidates.first
    }

    func entryCount(in range: Range<Date>, journal: Journal? = nil) -> Int {
        let lo = range.lowerBound
        let hi = range.upperBound
        var descriptor: FetchDescriptor<Entry>
        if let target = journal {
            let journalID = target.id
            descriptor = FetchDescriptor<Entry>(
                predicate: #Predicate {
                    $0.createdAt >= lo && $0.createdAt < hi && $0.journal?.id == journalID
                }
            )
        } else {
            descriptor = FetchDescriptor<Entry>(
                predicate: #Predicate { $0.createdAt >= lo && $0.createdAt < hi }
            )
        }
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func entriesForLastWeek(journal: Journal? = nil) -> [Entry] {
        let (start, end) = Self.previousWeekRange()
        var descriptor: FetchDescriptor<Entry>
        if let target = journal {
            let journalID = target.id
            descriptor = FetchDescriptor<Entry>(
                predicate: #Predicate {
                    $0.createdAt >= start && $0.createdAt < end && $0.journal?.id == journalID
                },
                sortBy: [SortDescriptor(\.createdAt)]
            )
        } else {
            descriptor = FetchDescriptor<Entry>(
                predicate: #Predicate { $0.createdAt >= start && $0.createdAt < end },
                sortBy: [SortDescriptor(\.createdAt)]
            )
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Generates and persists the weekly reflection for the previous week.
    /// Returns nil if AI is unavailable or generation fails.
    func generatePreviousWeekReflection(for journal: Journal?) async -> WeeklyReflection? {
        guard AIAvailability.isAvailable else { return nil }
        let entries = entriesForLastWeek(journal: journal)
        guard entries.count >= 3 else { return nil }
        return await generate(entries: entries, weekStart: Self.previousWeekStart(), journal: journal, replaceExisting: true)
    }

    /// Generates a reflection from the *current* in-progress week. Used by the
    /// manual "Generate reflection now" button so the writer can test or read
    /// before the week is over.
    func generateCurrentWeekReflection(for journal: Journal?) async -> WeeklyReflection? {
        guard AIAvailability.isAvailable else { return nil }
        let cal = Self.calendar
        let thisWeekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)) ?? .now
        let thisWeekEnd = cal.date(byAdding: .day, value: 7, to: thisWeekStart) ?? .now
        let entries = entriesInRange(thisWeekStart..<thisWeekEnd, journal: journal)
        guard !entries.isEmpty else { return nil }
        return await generate(entries: entries, weekStart: thisWeekStart, journal: journal, replaceExisting: true)
    }

    /// Internal — runs the generator and persists the reflection.
    private func generate(
        entries: [Entry],
        weekStart: Date,
        journal: Journal?,
        replaceExisting: Bool
    ) async -> WeeklyReflection? {
        if replaceExisting, let existing = existingReflection(for: weekStart, journal: journal) {
            context.delete(existing)
        }
        do {
            let response = try await ReflectionGenerator().generate(entries: entries)
            let reflection = WeeklyReflection(
                weekStartDate: weekStart,
                summary: response.summary,
                themes: response.themes,
                moodArc: response.moodArc
            )
            reflection.journal = journal
            context.insert(reflection)
            try? context.save()
            return reflection
        } catch {
            return nil
        }
    }

    private func entriesInRange(_ range: Range<Date>, journal: Journal?) -> [Entry] {
        let lo = range.lowerBound
        let hi = range.upperBound
        var descriptor: FetchDescriptor<Entry>
        if let target = journal {
            let journalID = target.id
            descriptor = FetchDescriptor<Entry>(
                predicate: #Predicate {
                    $0.createdAt >= lo && $0.createdAt < hi && $0.journal?.id == journalID
                },
                sortBy: [SortDescriptor(\.createdAt)]
            )
        } else {
            descriptor = FetchDescriptor<Entry>(
                predicate: #Predicate { $0.createdAt >= lo && $0.createdAt < hi },
                sortBy: [SortDescriptor(\.createdAt)]
            )
        }
        return (try? context.fetch(descriptor)) ?? []
    }
}
