/// Which of the working area's files are collapsed, as its changes are read again. The diff keeps a
/// file's collapsed state by its group and path, so staging or unstaging a file would make it a new
/// file to the diff, and expand it.
nonisolated enum WorkingAreaCollapse {
    /// A file that has left one group and arrived in another takes the state it had in the group it
    /// left. A file that was already shown, or that's new to the working area, keeps its own.
    static func following(_ collapsed: Set<DiffFile.Identity>, from previous: [DiffFile], to files: [DiffFile]) -> Set<DiffFile.Identity> {
        let previousIDs = Set(previous.map(\.id))
        let currentIDs = Set(files.map(\.id))
        var left: [String: DiffFile.Identity] = [:]
        for file in previous where !currentIDs.contains(file.id) {
            left[file.changed.path] = file.id
        }
        var result = collapsed
        for file in files where !previousIDs.contains(file.id) {
            guard let origin = left[file.changed.path] else { continue }
            if collapsed.contains(origin) {
                result.insert(file.id)
            } else {
                result.remove(file.id)
            }
        }
        return result
    }
}
