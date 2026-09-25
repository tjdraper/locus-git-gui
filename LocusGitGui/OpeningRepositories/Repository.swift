import Foundation

/// An opened repository: where its files are, and where Git keeps its own state for them. The Git
/// directory is usually `.git` at the top level, but a linked worktree's lives elsewhere.
nonisolated struct Repository: Equatable, Sendable {
    let workTree: URL
    let gitDirectory: URL
}
