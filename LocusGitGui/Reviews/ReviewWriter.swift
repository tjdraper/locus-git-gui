import Foundation
import os

/// Writes reviews off the main actor, one at a time, and only the latest version handed over for
/// each, however many arrive while a write is going on.
actor ReviewWriter {
    struct Key: Hashable, Sendable {
        let repository: String
        let review: UUID
    }

    private enum Pending {
        case write(Review)
        case delete
    }

    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "Reviews")

    private let folder: ReviewFolder
    private var pending: [Key: Pending] = [:]
    /// The newest version written or pending for each review, so an older one handed over late
    /// doesn't replace a newer one.
    private var newest: [Key: Int] = [:]
    private var deleted: Set<Key> = []
    private var writing: Task<Void, Never>?

    init(folder: ReviewFolder) {
        self.folder = folder
    }

    func write(_ review: Review, for key: Key, version: Int) {
        guard version > newest[key] ?? -1, !deleted.contains(key) else { return }
        newest[key] = version
        pending[key] = .write(review)
        startWriting()
    }

    /// A write handed over after this, from a save already under way, is dropped.
    func delete(_ key: Key) {
        deleted.insert(key)
        pending[key] = .delete
        startWriting()
    }

    /// Returns once everything handed over has been written, as the app quits.
    func finish() async {
        await writing?.value
    }

    private func startWriting() {
        if writing == nil {
            writing = Task { writePending() }
        }
    }

    private func writePending() {
        while let (key, next) = pending.first {
            pending[key] = nil
            do {
                switch next {
                case let .write(review): try folder.write(review, for: key.repository)
                case .delete: try folder.delete(key.review, for: key.repository)
                }
            } catch {
                Self.log.error("Saving a review failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
        writing = nil
    }
}
