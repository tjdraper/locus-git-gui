import Foundation
import os

/// Writes repositories' view state off the main actor, one at a time, and only the latest state
/// handed over for each, however many arrive while a write is going on.
actor RepositoryViewStateWriter {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "RepositoryViewState")

    private let files: RepositoryViewStateFiles
    private var pending: [String: (state: RepositoryViewState, version: Int)] = [:]
    /// The newest version written or pending for each repository, so an older state handed over
    /// late doesn't replace a newer one.
    private var newest: [String: Int] = [:]
    private var writing: Task<Void, Never>?

    init(files: RepositoryViewStateFiles) {
        self.files = files
    }

    /// `version` counts up with each state the store hands over for the repository.
    func write(_ state: RepositoryViewState, for repository: String, version: Int) {
        guard version > newest[repository] ?? -1 else { return }
        newest[repository] = version
        pending[repository] = (state, version)
        if writing == nil {
            writing = Task { await writePending() }
        }
    }

    /// Returns once everything handed over has been written, as the app quits.
    func finish() async {
        await writing?.value
    }

    func prune() {
        files.prune()
    }

    private func writePending() async {
        while let (repository, next) = pending.first {
            pending[repository] = nil
            do {
                try files.write(next.state, for: repository)
            } catch {
                Self.log.error("Saving a repository's view state failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
        writing = nil
    }
}
