import CryptoKit
import Foundation

/// Every review on this Mac, in a folder for each repository and a file for each review, since
/// comments make a review grow and a change to one shouldn't rewrite the rest.
nonisolated struct ReviewFolder: Sendable {
    private struct File: Codable {
        /// The repository's `id`, since its folder's name is only a hash of it.
        let repository: String
        let review: Review
    }

    let folder: URL

    /// Kept on this Mac only, alongside the repositories' view state.
    static var defaultFolder: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "com.buzzingpixel.LocusGitGui", directoryHint: .isDirectory)
            .appending(path: "Reviews", directoryHint: .isDirectory)
    }

    /// A file that can't be read is left out rather than failing the rest.
    func read(_ repository: String) -> [Review] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder(for: repository), includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(File.self, from: data),
                  file.repository == repository
            else { return nil }
            return file.review
        }
    }

    func write(_ review: Review, for repository: String) throws {
        let folder = folder(for: repository)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(File(repository: repository, review: review))
        try data.write(to: url(for: review.id, in: folder), options: .atomic)
    }

    func delete(_ review: UUID, for repository: String) throws {
        let url = url(for: review, in: folder(for: repository))
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func folder(for repository: String) -> URL {
        let hash = SHA256.hash(data: Data(repository.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: hash, directoryHint: .isDirectory)
    }

    private func url(for review: UUID, in folder: URL) -> URL {
        folder.appending(path: review.uuidString.lowercased() + ".json")
    }
}
