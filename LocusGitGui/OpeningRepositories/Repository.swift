import Foundation

/// An opened repository: where its files are, and where Git keeps its own state for them. The Git
/// directory is usually `.git` at the top level, but a linked worktree's lives elsewhere.
nonisolated struct Repository: Equatable, Sendable, Codable, Identifiable {
    let workTree: URL
    let gitDirectory: URL

    /// A repository is the same one when its working files are in the same place, even if its Git
    /// directory has moved.
    var id: String {
        workTree.standardizedFileURL.path
    }
}
