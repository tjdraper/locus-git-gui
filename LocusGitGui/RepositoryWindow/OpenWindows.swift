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

    struct HistoryWindow: Codable, Equatable, Sendable {
        let item: SidebarItemID
        var frame: String?
        var place: HistoryPlace?
    }

    struct WorkingAreaWindow: Codable, Equatable, Sendable {
        var frame: String?
        var filter = WorkingAreaFilter.all
    }

    var commits: [CommitWindow] = []
    var files: [FileWindow] = []
    var histories: [HistoryWindow] = []
    var workingArea: WorkingAreaWindow?
    var isActivityShown = false
}

nonisolated extension OpenWindows {
    /// Each field is optional when decoding, so a record saved before a kind of window existed
    /// still reads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commits = try container.decodeIfPresent([CommitWindow].self, forKey: .commits) ?? []
        files = try container.decodeIfPresent([FileWindow].self, forKey: .files) ?? []
        histories = try container.decodeIfPresent([HistoryWindow].self, forKey: .histories) ?? []
        workingArea = try container.decodeIfPresent(WorkingAreaWindow.self, forKey: .workingArea)
        isActivityShown = try container.decodeIfPresent(Bool.self, forKey: .isActivityShown) ?? false
    }
}
