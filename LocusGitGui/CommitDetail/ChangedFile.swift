import Foundation

/// A file a commit changed, from `git show --name-status -z`.
nonisolated struct ChangedFile: Equatable, Sendable {
    enum Change: Sendable {
        case added
        case copied
        case deleted
        case modified
        case renamed
        case typeChanged
        case unmerged
        case unknown

        /// Git's status letters. A rename or copy is followed by how similar the two files are,
        /// such as `R086`.
        init(letter: Character?) {
            switch letter {
            case "A": self = .added
            case "C": self = .copied
            case "D": self = .deleted
            case "M": self = .modified
            case "R": self = .renamed
            case "T": self = .typeChanged
            case "U": self = .unmerged
            default: self = .unknown
            }
        }

        var title: String {
            switch self {
            case .added: "Added"
            case .copied: "Copied"
            case .deleted: "Deleted"
            case .modified: "Modified"
            case .renamed: "Renamed"
            case .typeChanged: "Type Changed"
            case .unmerged: "Unmerged"
            case .unknown: "Changed"
            }
        }

        /// A rename or copy names the file it came from as well.
        var hasOriginalPath: Bool {
            self == .renamed || self == .copied
        }
    }

    let change: Change
    let path: String
    let originalPath: String?

    /// Each field ends in a NUL: the status, then the path, or for a rename or copy the path it
    /// came from and then the path it went to.
    static func parseList(_ output: Data) throws -> [ChangedFile] {
        var fields = output.split(separator: 0, omittingEmptySubsequences: false).makeIterator()
        var files: [ChangedFile] = []
        while let status = fields.next(), !status.isEmpty {
            let change = Change(letter: try UnreadableGitOutput.text(status).first)
            guard let first = fields.next(), !first.isEmpty else {
                throw UnreadableGitOutput(reason: "Changed file without a path")
            }
            if change.hasOriginalPath {
                guard let second = fields.next(), !second.isEmpty else {
                    throw UnreadableGitOutput(reason: "Rename without a new path")
                }
                files.append(ChangedFile(
                    change: change,
                    path: try UnreadableGitOutput.text(second),
                    originalPath: try UnreadableGitOutput.text(first)
                ))
            } else {
                files.append(ChangedFile(change: change, path: try UnreadableGitOutput.text(first), originalPath: nil))
            }
        }
        return files
    }
}
