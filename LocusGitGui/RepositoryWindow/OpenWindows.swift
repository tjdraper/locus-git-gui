/// The windows opened from a repository's window that were open when it was last seen, to open
/// again with it, after it's closed and reopened or the app is quit and opened again.
nonisolated struct OpenWindows: Codable, Equatable, Sendable {
    struct CommitWindow: Codable, Equatable, Sendable {
        let commit: String
        /// As `NSWindow.frameDescriptor` writes it.
        var frame: String?
    }

    struct FileWindow: Codable, Equatable, Sendable {
        /// Nil for a working area file.
        let commit: String?
        let file: DiffFile.Identity
        var frame: String?
        var scroll: DiffScrollAnchor?
    }

    struct WorkingAreaWindow: Codable, Equatable, Sendable {
        var frame: String?
        var filter = WorkingAreaFilter.all
    }

    var commits: [CommitWindow] = []
    var files: [FileWindow] = []
    var workingArea: WorkingAreaWindow?
    var isActivityShown = false
}
