import CryptoKit
import Foundation

/// Every repository's view state, a file each, so a change to one writes only its own and opening
/// one reads only its own. A repository's state holds where each of its diffs and histories was
/// left, which runs to hundreds of kilobytes for one used every day.
nonisolated struct RepositoryViewStateFiles: Sendable {
    private struct File: Codable {
        /// The repository's `id`, since the file's name is only a hash of it.
        let repository: String
        let state: RepositoryViewState
    }

    /// As many as the recent list keeps.
    static let limit = 1000

    let folder: URL

    /// Kept on this Mac only, since the repositories on it and where they are differ from other Macs'.
    static var defaultFolder: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "com.buzzingpixel.LocusGitGui", directoryHint: .isDirectory)
            .appending(path: "RepositoryViewStates", directoryHint: .isDirectory)
    }

    /// Nil for a repository never seen, or a file that can't be read.
    func read(_ repository: String) -> RepositoryViewState? {
        guard let data = try? Data(contentsOf: url(for: repository)),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.repository == repository
        else { return nil }
        return file.state
    }

    func write(_ state: RepositoryViewState, for repository: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(File(repository: repository, state: state))
        try data.write(to: url(for: repository), options: .atomic)
    }

    /// The least recently written go first, past the limit.
    func prune(keeping limit: Int = limit) {
        let manager = FileManager.default
        guard let urls = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]),
              urls.count > limit
        else { return }
        let byAge = urls.sorted { modified($0) < modified($1) }
        for url in byAge.prefix(urls.count - limit) {
            try? manager.removeItem(at: url)
        }
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    func url(for repository: String) -> URL {
        let hash = SHA256.hash(data: Data(repository.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: hash + ".json")
    }
}
