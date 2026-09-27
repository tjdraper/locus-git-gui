import Foundation

/// What the sidebar shows, what it's filtered by, and which of it is selected, collapsed or expanded.
@Observable
final class SidebarModel {
    /// Nil until the repository has been read once.
    private(set) var contents: SidebarContents?
    private(set) var pins = SidebarPins()
    var selection: SidebarItemID? {
        didSet { if selection != oldValue { onChange?() } }
    }

    var collapsedSections: Set<SidebarSection> {
        didSet { if collapsedSections != oldValue { onChange?() } }
    }

    var collapsedRemotes: Set<String> {
        didSet { if collapsedRemotes != oldValue { onChange?() } }
    }

    var filter: String {
        didSet { if filter != oldValue { onChange?() } }
    }

    /// Asks for the list to take focus, counted so every request is seen as a change.
    private(set) var focusRequests = 0
    private(set) var filterFocusRequests = 0
    /// Asks for the list to scroll to the selection.
    private(set) var revealRequests = 0

    @ObservationIgnored var onChange: (() -> Void)?
    /// For the pins to be written to the repository.
    @ObservationIgnored var onPinsChange: ((SidebarPins) -> Void)?
    /// An item's history in a window of its own, from the item's context menu.
    @ObservationIgnored var openInNewWindow: ((SidebarItemID) -> Void)?
    /// The commands in an item's context menu after Open in New Window and pinning, in groups.
    @ObservationIgnored var menuItems: ((SidebarItemID) -> [[SidebarMenuItem]])?
    /// A double-click, which checks out a branch.
    @ObservationIgnored var primaryAction: ((SidebarItemID) -> Void)?
    /// A branch dragged onto another, to merge or rebase.
    @ObservationIgnored var drop: ((_ dragged: SidebarItemID, _ target: SidebarItemID) -> Void)?
    @ObservationIgnored private var typeSelect = SidebarTypeSelect()

    init(state: RepositoryViewState) {
        selection = state.selection
        collapsedSections = state.collapsedSections
        collapsedRemotes = state.collapsedRemotes
        filter = state.sidebarFilter
    }

    /// A selection that's gone, such as a deleted branch or a dropped stash, is cleared. Until the
    /// first read, the remembered selection is kept, since nothing is known to be gone yet.
    func show(_ contents: SidebarContents, pins: SidebarPins) {
        self.pins = pins
        let contents = contents.pinning(pins)
        guard contents != self.contents else { return }
        self.contents = contents
        if let selection, !contents.contains(selection) {
            self.selection = nil
        }
    }

    /// Shown at once, ahead of the pins being written and read back.
    func togglePin(_ id: SidebarItemID) {
        guard let contents, SidebarPins.canPin(id) else { return }
        pins.toggle(id)
        self.contents = contents.pinning(pins)
        onPinsChange?(pins)
        if id == selection {
            revealRequests += 1
        }
    }

    var isFiltering: Bool {
        !filter.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var visibleContents: SidebarContents? {
        contents?.filtered(by: filter)
    }

    func requestFocus() {
        focusRequests += 1
    }

    func requestFilterFocus() {
        filterFocusRequests += 1
    }

    /// Selects it with the list focused, first clearing a filter that hides it and expanding the
    /// section and remote it's in.
    func reveal(_ id: SidebarItemID) {
        guard let contents, let section = contents.section(containing: id) else { return }
        if isFiltering, visibleContents?.contains(id) != true {
            filter = ""
        }
        collapsedSections.remove(section)
        if let remote = contents.remote(containing: id) {
            collapsedRemotes.remove(remote)
        }
        selection = id
        revealRequests += 1
        requestFocus()
    }

    /// Everything is expanded while filtering, so no match is hidden in a collapsed section.
    func isExpanded(_ section: SidebarSection) -> Bool {
        isFiltering || !collapsedSections.contains(section)
    }

    func setExpanded(_ isExpanded: Bool, _ section: SidebarSection) {
        guard !isFiltering else { return }
        if isExpanded {
            collapsedSections.remove(section)
        } else {
            collapsedSections.insert(section)
        }
    }

    func isExpanded(remote: String) -> Bool {
        isFiltering || !collapsedRemotes.contains(remote)
    }

    func setExpanded(_ isExpanded: Bool, remote: String) {
        guard !isFiltering else { return }
        if isExpanded {
            collapsedRemotes.remove(remote)
        } else {
            collapsedRemotes.insert(remote)
        }
    }

    func typeSelect(_ characters: String) {
        guard let contents = visibleContents else { return }
        let rows = isFiltering
            ? contents.visibleRows(collapsedSections: [], collapsedRemotes: [])
            : contents.visibleRows(collapsedSections: collapsedSections, collapsedRemotes: collapsedRemotes)
        let selected = rows.firstIndex { $0.id == selection }
        if let index = typeSelect.select(typing: characters, at: .now, in: rows.map(\.name), selected: selected) {
            selection = rows[index].id
        }
    }
}
