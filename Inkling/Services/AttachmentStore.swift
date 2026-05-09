import Foundation
import UIKit

/// Disk-backed photo (and later audio) attachment storage.
///
/// Files live at: `Application Support/Inkling/attachments/<entryID>/<filename>`
/// Filenames are referenced by the SwiftData `Entry` model — no binary blobs in the store.
struct AttachmentStore {
    enum AttachmentError: Error {
        case directoryUnavailable
        case writeFailed(underlying: Error)
        case readFailed
    }

    // MARK: Locations

    static var rootDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(filePath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Inkling", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
    }

    static func directory(for entryID: UUID) -> URL {
        rootDirectory.appendingPathComponent(entryID.uuidString, isDirectory: true)
    }

    static func url(for entryID: UUID, filename: String) -> URL {
        directory(for: entryID).appendingPathComponent(filename)
    }

    // MARK: Photos

    /// Persists a JPEG-encoded photo to disk and returns the filename written.
    @discardableResult
    static func savePhoto(_ data: Data, for entryID: UUID) throws -> String {
        let dir = directory(for: entryID)
        try ensureDirectory(at: dir)

        let filename = "\(UUID().uuidString).jpg"
        let target = dir.appendingPathComponent(filename)
        do {
            try data.write(to: target, options: [.atomic])
        } catch {
            throw AttachmentError.writeFailed(underlying: error)
        }
        return filename
    }

    /// Encodes a UIImage as JPEG (q=0.85) and persists it.
    @discardableResult
    static func savePhoto(_ image: UIImage, for entryID: UUID) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw AttachmentError.readFailed
        }
        return try savePhoto(data, for: entryID)
    }

    static func loadPhoto(filename: String, for entryID: UUID) -> UIImage? {
        let url = url(for: entryID, filename: filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func deletePhoto(filename: String, for entryID: UUID) {
        let url = url(for: entryID, filename: filename)
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes the entire attachments folder for an entry. Call on entry delete.
    static func deleteAllAttachments(for entryID: UUID) {
        let dir = directory(for: entryID)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Helpers

    private static func ensureDirectory(at url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw AttachmentError.directoryUnavailable
        }
    }
}
