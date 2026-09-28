import Foundation

/// Resolving a conflict by taking a whole version of the file: for one deleted on one side and
/// changed on the other, deleted on both, a binary file, a symbolic link or a submodule, where
/// there are no lines to pick between. Each choice stages the file, which marks it resolved.
nonisolated enum ConflictVersionChoice: Equatable, Sendable {
    case ours
    case theirs
    case delete

    /// The versions the file has, and deleting it when either side deleted it.
    static func choices(for stages: ConflictStages) -> [ConflictVersionChoice] {
        switch (stages.ours, stages.theirs) {
        case (.some, .some): [.ours, .theirs]
        case (.some, nil): [.ours, .delete]
        case (nil, .some): [.theirs, .delete]
        case (nil, nil): [.delete]
        }
    }

    /// A submodule is put in the index directly, since `git checkout --ours` doesn't take one.
    func commands(for path: String, stages: ConflictStages) -> [GitCommand] {
        let pathspec = ":(literal)" + path
        let version: ConflictStages.Version?
        let flag: String
        switch self {
        case .ours:
            version = stages.ours
            flag = "--ours"
        case .theirs:
            version = stages.theirs
            flag = "--theirs"
        case .delete:
            // Forced, since the file left in the working tree is a side's changed version, which
            // differs from what's staged. That version is still in its commit.
            return [.changing(["rm", "--force", "--quiet", "--", pathspec])]
        }
        guard let version else { return [] }
        if version.isSubmodule {
            return [.changing(["update-index", "--cacheinfo", "\(version.mode),\(version.object),\(path)"])]
        }
        return [
            .changing(["checkout", flag, "--", pathspec]),
            .changing(["add", "--", pathspec]),
        ]
    }
}
