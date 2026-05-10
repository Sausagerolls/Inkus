import Foundation
import SwiftData
import UIKit

/// SwiftData-backed attachment storage. Binary blobs live in the Attachment
/// @Model with `.externalStorage`, which CloudKit then syncs as CKAssets when
/// the container is CloudKit-backed.
///
/// This file used to read and write to `Application Support/.../attachments/`.
/// Those files are now migrated into Attachment rows on first launch via
/// `migrateLegacyFilesIfNeeded(in:)`, called from the model container setup.
@MainActor
enum AttachmentStore {
    enum AttachmentError: Error {
        case encodeFailed
        case writeFailed(underlying: Error)
    }

    // MARK: New API — SwiftData-backed

    /// Persist a JPEG-encoded photo to the entry's attachments and return the row.
    @discardableResult
    static func savePhoto(_ data: Data, to entry: Entry, in context: ModelContext) throws -> Attachment {
        let filename = "photo-\(timestamp()).jpg"
        let attachment = Attachment(kind: .photo, filename: filename, data: data)
        attachment.entry = entry
        context.insert(attachment)
        try? context.save()
        return attachment
    }

    /// Encode a UIImage as JPEG and persist as a photo attachment.
    @discardableResult
    static func savePhoto(_ image: UIImage, to entry: Entry, in context: ModelContext) throws -> Attachment {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw AttachmentError.encodeFailed
        }
        return try savePhoto(data, to: entry, in: context)
    }

    /// Persist a JPEG-encoded scanned page.
    @discardableResult
    static func saveScan(_ data: Data, to entry: Entry, in context: ModelContext) throws -> Attachment {
        let filename = "scan-\(timestamp()).jpg"
        let attachment = Attachment(kind: .scan, filename: filename, data: data)
        attachment.entry = entry
        context.insert(attachment)
        try? context.save()
        return attachment
    }

    /// Persist a PencilKit drawing — both the rendered PNG (for previews) and
    /// the original `PKDrawing.dataRepresentation()` so the user can re-edit.
    @discardableResult
    static func saveDrawing(
        rendered pngData: Data,
        vectorData: Data,
        kind: AttachmentKind = .drawing,
        to entry: Entry,
        in context: ModelContext
    ) throws -> Attachment {
        let prefix = (kind == .scan ? "scan-marked" : "doodle")
        let filename = "\(prefix)-\(timestamp()).png"
        let attachment = Attachment(kind: kind, filename: filename, data: pngData, vectorData: vectorData)
        attachment.entry = entry
        context.insert(attachment)
        try? context.save()
        return attachment
    }

    static func image(from attachment: Attachment) -> UIImage? {
        guard let data = attachment.data else { return nil }
        return UIImage(data: data)
    }

    static func delete(_ attachment: Attachment, in context: ModelContext) {
        context.delete(attachment)
        try? context.save()
    }

    // MARK: Migration from legacy on-disk attachments

    /// Walks every Entry, finds rows that still carry legacy `photoFilenames`
    /// pointing at on-disk JPEGs in `Application Support/Inkling/attachments/`,
    /// imports them as Attachment rows, and clears the legacy arrays.
    /// Idempotent — safe to call on every launch.
    static func migrateLegacyFilesIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { !$0.photoFilenames.isEmpty || !$0.audioFilenames.isEmpty }
        )
        let entries = (try? context.fetch(descriptor)) ?? []
        guard !entries.isEmpty else { return }

        for entry in entries {
            let entryID = entry.id
            for filename in entry.photoFilenames {
                let url = legacyDirectory(for: entryID).appendingPathComponent(filename)
                guard let data = try? Data(contentsOf: url) else { continue }
                let imported = Attachment(kind: .photo, filename: filename, data: data)
                imported.entry = entry
                context.insert(imported)
            }
            // Audio carries through as filenames-only since we never shipped
            // recording UI; clear the array but don't drop the source files.
            entry.photoFilenames = []
            entry.audioFilenames = []
        }
        try? context.save()

        // Best-effort cleanup of the legacy directory tree. Keep silent on
        // failure; nothing depends on it being gone.
        try? FileManager.default.removeItem(at: legacyRoot)
    }

    // MARK: Legacy paths (only referenced by the migration)

    private static var legacyRoot: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(filePath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Inkling", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
    }

    private static func legacyDirectory(for entryID: UUID) -> URL {
        legacyRoot.appendingPathComponent(entryID.uuidString, isDirectory: true)
    }

    // MARK: Helpers

    private static func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime]
        return f.string(from: .now).replacingOccurrences(of: ":", with: "-")
    }
}
