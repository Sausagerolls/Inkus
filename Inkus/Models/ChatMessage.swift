import Foundation
import SwiftData

/// One turn in a `ChatThread`. Persisted + CloudKit-synced.
@Model
final class ChatMessage {
    var id: UUID = UUID()
    var roleRaw: String = ChatRole.user.rawValue
    var content: String = ""
    var createdAt: Date = Date.now

    var thread: ChatThread?

    var role: ChatRole {
        ChatRole(rawValue: roleRaw) ?? .user
    }

    init(role: ChatRole, content: String, thread: ChatThread? = nil) {
        self.id = UUID()
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = .now
        self.thread = thread
    }
}

enum ChatRole: String, Codable {
    case user
    case assistant
}
