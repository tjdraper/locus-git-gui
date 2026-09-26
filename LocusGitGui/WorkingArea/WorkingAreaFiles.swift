/// The working area's files as the diff lists them: each group in turn, and in each, the files as
/// `git status` ordered them. A file with staged and unstaged changes is in both groups, each with
/// the modes and objects of its own two sides.
nonisolated enum WorkingAreaFiles {
    struct Entry: Equatable, Sendable {
        let group: WorkingAreaGroup
        let file: ChangedFile
    }

    static func list(_ status: RepositoryStatus) -> [Entry] {
        var byGroup: [WorkingAreaGroup: [ChangedFile]] = [:]
        for file in status.files {
            switch file.state {
            case let .changed(staged, unstaged):
                if let staged {
                    byGroup[.staged, default: []].append(stagedSide(of: file, change: staged))
                }
                if let unstaged {
                    byGroup[.unstaged, default: []].append(unstagedSide(of: file, change: unstaged))
                }
            case .conflicted:
                byGroup[.conflicted, default: []].append(ChangedFile(change: .unmerged, path: file.path, originalPath: nil))
            case .untracked:
                byGroup[.untracked, default: []].append(ChangedFile(change: .added, path: file.path, originalPath: nil))
            case .ignored:
                break
            }
        }
        return WorkingAreaGroup.allCases.flatMap { group in
            (byGroup[group] ?? []).map { Entry(group: group, file: $0) }
        }
    }

    /// HEAD against the index.
    private static func stagedSide(of file: RepositoryStatus.File, change: RepositoryStatus.Change) -> ChangedFile {
        let versions = file.versions
        return ChangedFile(
            change: ChangedFile.Change(change),
            path: file.path,
            originalPath: file.originalPath,
            oldMode: versions?.headMode ?? ChangedFile.absentMode,
            newMode: versions?.indexMode ?? ChangedFile.absentMode,
            oldObject: versions.flatMap { object($0.headObject) },
            newObject: versions.flatMap { object($0.indexObject) }
        )
    }

    /// The index against the working tree, whose side has no object until it's staged. A rename is
    /// staged, so here the file is only ever at its new path.
    private static func unstagedSide(of file: RepositoryStatus.File, change: RepositoryStatus.Change) -> ChangedFile {
        let versions = file.versions
        return ChangedFile(
            change: ChangedFile.Change(change),
            path: file.path,
            originalPath: nil,
            oldMode: versions?.indexMode ?? ChangedFile.absentMode,
            newMode: versions?.workTreeMode ?? ChangedFile.absentMode,
            oldObject: versions.flatMap { object($0.indexObject) },
            newObject: nil
        )
    }

    private static func object(_ hash: String) -> String? {
        hash.allSatisfy { $0 == "0" } ? nil : hash
    }
}

nonisolated extension ChangedFile.Change {
    init(_ change: RepositoryStatus.Change) {
        self.init(letter: change.rawValue)
    }
}
