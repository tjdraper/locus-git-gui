/// A file's changes to open in a window of their own, with the rest of the files they came with for
/// the window's Previous File and Next File.
struct FileWindowRequest {
    enum Source: Equatable {
        case commit(Commit)
        /// The file's staged, unstaged or untracked changes, which the window keeps up with.
        case workingArea
    }

    let source: Source
    let file: DiffFile
    let files: [DiffFile]
}
