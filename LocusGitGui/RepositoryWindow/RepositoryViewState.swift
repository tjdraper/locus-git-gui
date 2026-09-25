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
    /// Nil until the window has been laid out once.
    var columns: Columns?
    /// As `NSWindow.frameDescriptor` writes it, which records the screen as well as the frame.
    var windowFrame: String?
}

nonisolated extension RepositoryViewState {
    /// Each field is optional when decoding, so a state saved before a field existed still reads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selection = try container.decodeIfPresent(SidebarItemID.self, forKey: .selection)
        collapsedSections = try container.decodeIfPresent(Set<SidebarSection>.self, forKey: .collapsedSections) ?? []
        collapsedRemotes = try container.decodeIfPresent(Set<String>.self, forKey: .collapsedRemotes) ?? []
        columns = try container.decodeIfPresent(Columns.self, forKey: .columns)
        windowFrame = try container.decodeIfPresent(String.self, forKey: .windowFrame)
    }
}
