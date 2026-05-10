import Foundation
import SwiftData

/// CloudKit-syncable attachment storage. Binary blob lives in the SwiftData
/// store via `.externalStorage` so SwiftData/CloudKit handles the heavy
/// lifting and we don't have to ship a parallel file-sync system.
///
/// Kinds correspond to the editor's attachment buttons:
///   - `photo`    → JPEG from the photo library
///   - `audio`    → recorded audio (future)
///   - `scan`     → JPEG from VisionKit's document scanner; may carry markup
///   - `drawing`  → PNG render of a PencilKit doodle; the underlying
///                  `PKDrawing.dataRepresentation()` is stored alongside in
///                  `vectorData` so the user can re-edit the strokes later.
@Model
final class Attachment {
    // CloudKit constraints: no .unique, every property optional or default.
    var id: UUID = UUID()
    var kindRaw: String = AttachmentKind.photo.rawValue
    var createdAt: Date = Date.now

    /// Display filename for export (e.g. `scan-2026-05-10.jpg`).
    var filename: String = ""

    /// Rasterised pixels — JPEG for photos/scans, PNG for drawings.
    /// Stored externally on disk by SwiftData; CloudKit syncs as CKAsset
    /// when the container is CloudKit-backed.
    @Attribute(.externalStorage) var data: Data?

    /// Optional vector data for editable kinds (currently only PencilKit
    /// drawings — `PKDrawing.dataRepresentation()`). Allows non-destructive
    /// re-edit later. Nil for photos and unmarked scans.
    @Attribute(.externalStorage) var vectorData: Data?

    /// Back-reference set by the @Relationship on Entry.
    var entry: Entry?

    init(kind: AttachmentKind, filename: String, data: Data, vectorData: Data? = nil) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.createdAt = .now
        self.filename = filename
        self.data = data
        self.vectorData = vectorData
    }

    var kind: AttachmentKind {
        get { AttachmentKind(rawValue: kindRaw) ?? .photo }
        set { kindRaw = newValue.rawValue }
    }
}

enum AttachmentKind: String, Codable, CaseIterable, Sendable {
    case photo
    case audio
    case scan
    case drawing
}
