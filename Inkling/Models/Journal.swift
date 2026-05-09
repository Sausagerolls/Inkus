import Foundation
import SwiftData

@Model
final class Journal {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconName: String       // SF Symbol identifier
    var accentColorHex: String // e.g. "#4F46E5"
    var sortOrder: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Entry.journal)
    var entries: [Entry] = []

    @Relationship(deleteRule: .cascade, inverse: \WeeklyReflection.journal)
    var reflections: [WeeklyReflection] = []

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
