import Foundation
import SwiftData

/// A persisted conversation with the on-device journaling companion.
///
/// Two surfaces produce threads:
///   • `.talk`   — full-screen Talk tab. Open-ended, knows the writer's
///                 last 14 days of entries as background.
///   • `.editor` — small sheet pinned to a single draft Entry. Knows only
///                 that draft's body. `entry` points at it.
@Model
final class ChatThread {
    // CloudKit constraints: no .unique, every property optional or with default.
    var id: UUID = UUID()
    var title: String = "New chat"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// "talk" or "editor" — see `ChatSurfaceKind`. Stored as raw string so
    /// CloudKit doesn't choke on a Swift enum.
    var surfaceRaw: String = ChatSurfaceKind.talk.rawValue

    /// Set only for editor-surface threads. Lets the in-editor sheet find
    /// the most-recent thread for the draft it's pinned to.
    var entry: Entry?

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.thread)
    var messages: [ChatMessage]? = []

    var surface: ChatSurfaceKind {
        ChatSurfaceKind(rawValue: surfaceRaw) ?? .talk
    }

    init(title: String = "New chat", surface: ChatSurfaceKind = .talk, entry: Entry? = nil) {
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.updatedAt = .now
        self.surfaceRaw = surface.rawValue
        self.entry = entry
    }
}

enum ChatSurfaceKind: String, Codable {
    case talk
    case editor
}
