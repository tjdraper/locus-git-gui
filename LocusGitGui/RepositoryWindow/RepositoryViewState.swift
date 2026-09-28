import Foundation

/// How a repository's window was left, so reopening the repository later puts it back that way.
nonisolated struct RepositoryViewState: Codable, Equatable, Sendable {
    struct Columns: Codable, Equatable, Sendable {
        /// The width the sidebar has when shown, kept while it's hidden.
        var sidebarWidth: Double
        var historyWidth: Double
        var isSidebarCollapsed: Bool
    }

    var selection: SidebarItemID?
    var collapsedSections: Set<SidebarSection> = []
    var collapsedRemotes: Set<String> = []
    var sidebarFilter = ""
    /// What Find in History was left looking for.
    var findText = ""
    var findField = HistorySearch.Field.message
    var workingAreaFilter = WorkingAreaFilter.all
    /// Nil until the window has been laid out once.
    var columns: Columns?
    /// As `NSWindow.frameDescriptor` writes it, which records the screen as well as the frame.
    var windowFrame: String?
    var diffChoices = DiffOptionChoices()
    /// View > Show Message as Markdown.
    var showsMessageAsMarkdown = true
    var diffPlaces = DiffPlaceMemory()
    var historyPlaces = HistoryPlaceMemory()
    var openWindows = OpenWindows()
    /// A commit message written and not yet committed, so closing the window doesn't lose it.
    var commitDraft: CommitMessage?
}

nonisolated extension RepositoryViewState {
    /// Each field is optional when decoding, so a state saved before a field existed still reads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selection = try container.decodeIfPresent(SidebarItemID.self, forKey: .selection)
        collapsedSections = try container.decodeIfPresent(Set<SidebarSection>.self, forKey: .collapsedSections) ?? []
        collapsedRemotes = try container.decodeIfPresent(Set<String>.self, forKey: .collapsedRemotes) ?? []
        sidebarFilter = try container.decodeIfPresent(String.self, forKey: .sidebarFilter) ?? ""
        findText = try container.decodeIfPresent(String.self, forKey: .findText) ?? ""
        findField = try container.decodeIfPresent(HistorySearch.Field.self, forKey: .findField) ?? .message
        workingAreaFilter = try container.decodeIfPresent(WorkingAreaFilter.self, forKey: .workingAreaFilter) ?? .all
        columns = try container.decodeIfPresent(Columns.self, forKey: .columns)
        windowFrame = try container.decodeIfPresent(String.self, forKey: .windowFrame)
        diffChoices = try container.decodeIfPresent(DiffOptionChoices.self, forKey: .diffChoices)
            ?? Self.legacyDiffChoices(from: decoder)
        showsMessageAsMarkdown = try container.decodeIfPresent(Bool.self, forKey: .showsMessageAsMarkdown) ?? true
        diffPlaces = try container.decodeIfPresent(DiffPlaceMemory.self, forKey: .diffPlaces) ?? DiffPlaceMemory()
        historyPlaces = try container.decodeIfPresent(HistoryPlaceMemory.self, forKey: .historyPlaces) ?? HistoryPlaceMemory()
        openWindows = try container.decodeIfPresent(OpenWindows.self, forKey: .openWindows) ?? OpenWindows()
        commitDraft = try container.decodeIfPresent(CommitMessage.self, forKey: .commitDraft)
    }

    private enum LegacyKeys: String, CodingKey {
        case diffOptions
    }

    /// Saved before Settings had diff defaults, when every repository kept both options whether or
    /// not they'd been changed. Only the ones changed from Git's defaults count as choices.
    private static func legacyDiffChoices(from decoder: any Decoder) throws -> DiffOptionChoices {
        let container = try decoder.container(keyedBy: LegacyKeys.self)
        guard let options = try container.decodeIfPresent(DiffOptions.self, forKey: .diffOptions) else {
            return DiffOptionChoices()
        }
        return DiffOptionChoices(options, defaults: DiffOptions())
    }
}
