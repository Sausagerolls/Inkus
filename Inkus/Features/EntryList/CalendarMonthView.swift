import SwiftUI
import SwiftData

/// Month-grid calendar with dots on days that have entries in the given journal.
/// Tapping a day calls `onSelectDate` so the parent can scope its list to that day.
struct CalendarMonthView: View {
    let journal: Journal
    let accent: Color
    let onSelectDate: (Date) -> Void

    @State private var anchor: Date = Calendar.current.startOfDay(for: .now)
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)

    @Query private var entries: [Entry]

    init(journal: Journal, accent: Color, onSelectDate: @escaping (Date) -> Void) {
        self.journal = journal
        self.accent = accent
        self.onSelectDate = onSelectDate
        let journalID = journal.id
        _entries = Query(
            filter: #Predicate<Entry> { entry in
                entry.journal?.id == journalID
            },
            sort: [SortDescriptor(\Entry.createdAt, order: .reverse)]
        )
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        return c
    }

    private var daysWithEntries: Set<Date> {
        Set(entries.map { calendar.startOfDay(for: $0.createdAt) })
    }

    private var monthInterval: DateInterval {
        calendar.dateInterval(of: .month, for: anchor) ?? DateInterval(start: anchor, duration: 0)
    }

    private var weekdaySymbols: [String] {
        // Rotated to start on Monday.
        let symbols = calendar.veryShortWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    private var monthDayCells: [DayCell] {
        let firstOfMonth = calendar.startOfDay(for: monthInterval.start)
        let firstWeekdayOfMonth = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (firstWeekdayOfMonth - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30

        var cells: [DayCell] = []
        for _ in 0..<leadingBlanks {
            cells.append(.blank)
        }
        for d in 1...daysInMonth {
            if let day = calendar.date(byAdding: .day, value: d - 1, to: firstOfMonth) {
                cells.append(.day(day))
            }
        }
        return cells
    }

    private var monthTitle: String {
        anchor.formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
        VStack(spacing: Spacing.m) {
            header
            weekdayRow
            grid
            entriesForSelectedDay
        }
    }

    private var header: some View {
        HStack {
            Button { step(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.inkSecondary))
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(monthTitle)
                .font(.system(.title3, design: .serif).weight(.semibold))
            Spacer()
            Button { step(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.inkSecondary))
            }
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, Spacing.m)
    }

    private var weekdayRow: some View {
        HStack {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Spacing.m)
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let entryDays = daysWithEntries
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(monthDayCells.enumerated()), id: \.offset) { _, cell in
                switch cell {
                case .blank:
                    Color.clear.frame(height: 40)
                case .day(let date):
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
                    let isToday    = calendar.isDateInToday(date)
                    let hasEntry   = entryDays.contains(calendar.startOfDay(for: date))
                    Button {
                        selectedDay = date
                        onSelectDate(date)
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(calendar.component(.day, from: date))")
                                .font(.callout.weight(isToday ? .bold : .regular))
                                .foregroundStyle(isSelected ? Color.white : .primary)
                            Circle()
                                .fill(hasEntry ? (isSelected ? Color.white : accent) : Color.clear)
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? accent : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isToday && !isSelected ? accent : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide).month().day()))\(hasEntry ? ", has entries" : "")")
                }
            }
        }
        .padding(.horizontal, Spacing.m)
    }

    private var selectedDayEntries: [Entry] {
        let start = calendar.startOfDay(for: selectedDay)
        let end   = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return entries.filter { $0.createdAt >= start && $0.createdAt < end }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @ViewBuilder
    private var entriesForSelectedDay: some View {
        let dayEntries = selectedDayEntries
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text(headerLabel(for: selectedDay))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(dayEntries.count) \(dayEntries.count == 1 ? "entry" : "entries")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.m)
            if dayEntries.isEmpty {
                Text("No entries on this day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.l)
            } else {
                ForEach(dayEntries) { entry in
                    NavigationLink(value: entry) {
                        EntryRowView(entry: entry)
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, Spacing.s)
                            .background(Color.inkSecondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, Spacing.m)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, Spacing.m)
    }

    private func step(by months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: anchor) {
            anchor = calendar.startOfDay(for: next)
        }
    }

    private func headerLabel(for date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }

    private enum DayCell {
        case blank
        case day(Date)
    }
}
