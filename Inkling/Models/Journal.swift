import Foundation
import SwiftData

@Model
final class Journal {
    // CloudKit constraints: no .unique attributes; every property optional or with default.
    var id: UUID = UUID()
    var name: String = "Journal"
    var iconName: String = "book.closed"   // SF Symbol identifier
    var accentColorHex: String = "#4F46E5"
    var sortOrder: Int = 0
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Entry.journal)
    var entries: [Entry]? = []

    @Relationship(deleteRule: .cascade, inverse: \WeeklyReflection.journal)
    var reflections: [WeeklyReflection]? = []

    init(
        name: String,
        iconName: String = "book.closed",
        accentColorHex: String = "#4F46E5",
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.accentColorHex = accentColorHex
        self.sortOrder = sortOrder
        self.createdAt = .now
    }
}
