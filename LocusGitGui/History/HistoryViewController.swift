import AppKit
import SwiftUI

/// The middle column: the history of whatever the sidebar has selected, with Find above it. A table
/// rather than a SwiftUI list, which stops keeping up long before a history of a million commits.
final class HistoryViewController: NSViewController {
    /// Commands the window passes on to the history from whichever column has focus, since they
    /// act on the history wherever the user is.
    static let windowActions: Set<Selector> = [
        #selector(copyCommitHash(_:)),
        #selector(copyCommitSubject(_:)),
        #selector(findInHistory(_:)),
        #selector(findByMessage(_:)),
        #selector(findByAuthor(_:)),
        #selector(findInChanges(_:)),
    ]

    /// Waits for a pause in typing, since each search is a `git log` over the whole history.
    private static let searchDelay: Duration = .milliseconds(300)

    var onSelect: ((Commit?) -> Void)?
    var reveal: ((SidebarItemID) -> Void)?
    var showFailure: ((GitFailure, _ retry: @escaping () -> Void) -> Void)?

    private(set) var selectedCommit: Commit?
    let table = NSTableView()
    private let list: HistoryList
    private let scrollView = NSScrollView()
    private lazy var find = HistoryFindField(menuItems: [AppCommand.findByMessage, .findByAuthor, .findInChanges].map { command in
        command.makeMenuItem(target: self)
    })
    private let placeholder = HistoryPlaceholder()
    private lazy var placeholderView = NSHostingView(rootView: HistoryPlaceholderView(model: placeholder))
    private lazy var contextMenu = HistoryContextMenu(
        commitForMenu: { [weak self] in self?.commit(at: self?.table.clickedRow ?? -1) },
        labels: { [weak self] hash in self?.labels[hash] ?? [] },
        parentTitle: { [weak self] hash in self?.title(ofCommit: hash) ?? hash },
        goToCommit: { [weak self] hash in self?.goToCommit(hash) },
        reveal: { [weak self] id in self?.reveal?(id) }
    )
    private var labels: [String: [CommitRefLabel]] = [:]
    private var scope: HistoryScope?
    /// Selection changes the history makes itself, rather than the user.
    private var isRestoringSelection = false
    private var pendingSearch: Task<Void, Never>?
    private var goingToCommit: Task<Void, Never>?

    init(list: HistoryList) {
        self.list = list
        super.init(nibName: nil, bundle: nil)
        list.onChange = { [weak self] change in self?.listChanged(change) }
        placeholder.showDetails = { [weak self] in
            guard let self, let failure = list.failure else { return }
            showFailure?(failure) { [weak self] in self?.list.reload() }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    var findField: NSSearchField {
        find.field
    }

    override func loadView() {
        let view = NSView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Commit"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .inset
        table.rowHeight = HistoryRowView.height
        // Rows meet with no gap, so the graph's lines run on from one row into the next.
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.allowsTypeSelect = false
        table.dataSource = self
        table.delegate = self
        table.menu = contextMenu.menu
        table.setAccessibilityLabel("History")
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.drawsBackground = false
        // Pinned over the list, so the list sets its size. SwiftUI's would fix the window's height
        // to whatever the placeholder shows, which for nothing is zero.
        placeholderView.sizingOptions = []
        find.onChange = { [weak self] in self?.searchSoon() }
        find.moveToList = { [weak self] in self?.focusList() }

        for subview in [find.field, scrollView, placeholderView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            find.field.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            find.field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            find.field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: find.field.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholderView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
        ])
        self.view = view
        updatePlaceholder()
    }

    /// Asked on every refresh, and only read again when the commits it starts from have moved.
    func show(_ scope: HistoryScope, isSameSelection: Bool) {
        self.scope = scope
        list.show(scope, search: find.search, isSameSelection: isSameSelection)
    }

    /// Redrawn only when a label has moved, since a refresh asks after every change to the files.
    func showLabels(_ labels: [String: [CommitRefLabel]]) {
        guard labels != self.labels else { return }
        self.labels = labels
        let visible = table.rows(in: table.visibleRect)
        guard visible.length > 0 else { return }
        table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location ..< NSMaxRange(visible)), columnIndexes: [0])
    }

    func labels(of commit: Commit) -> [CommitRefLabel] {
        labels[commit.hash] ?? []
    }

    /// Reads on down the history until it reaches the commit, for a parent well below its child.
    /// A newer go-to, or the user choosing another commit, cancels one still reading.
    func goToCommit(_ hash: String) {
        goingToCommit?.cancel()
        // A search's results rarely hold a commit's parent, and reading on through all of them to
        // be sure would search the history again for every page.
        if list.search != nil, list.index(of: hash) == nil {
            NSSound.beep()
            return
        }
        goingToCommit = Task { [weak self] in
            let index = await self?.list.find(hash)
            guard !Task.isCancelled, let self else { return }
            guard let index else {
                NSSound.beep()
                return
            }
            table.selectRowIndexes([index], byExtendingSelection: false)
            table.scrollRowToVisible(index)
            focusList()
        }
    }

    /// A parent's short hash and subject when it's been read, and only its short hash otherwise.
    func title(ofCommit hash: String) -> String {
        let short = String(hash.prefix(7))
        guard let index = list.index(of: hash) else { return short }
        return "\(short)  \(list.commits[index].subject)"
    }

    /// The selected commit's parents, for Go to Parent.
    var parentChoices: [CommandPaletteDestination] {
        (selectedCommit?.parents ?? []).map { hash in
            CommandPaletteDestination(id: "commit:\(hash)", kind: .commit, title: title(ofCommit: hash)) { [weak self] in
                self?.goToCommit(hash)
            }
        }
    }

    /// The selected commit's branches and tags, for Reveal in Sidebar.
    var labelChoices: [CommandPaletteDestination] {
        guard let selectedCommit else { return [] }
        return labels(of: selectedCommit).compactMap { label in
            guard case let .ref(name) = label.sidebarItem else { return nil }
            let kind: CommandPaletteDestination.Kind = switch label.kind {
            case .remoteBranch: .remoteBranch
            case .tag: .tag
            case .head, .checkedOutBranch, .branch: .branch
            }
            return CommandPaletteDestination(id: "ref:\(name)", kind: kind, title: label.name) { [weak self] in
                self?.reveal?(.ref(name))
            }
        }
    }

    func focusFind() {
        view.window?.makeFirstResponder(find.field)
    }

    func focusList() {
        if table.selectedRow < 0, table.numberOfRows > 0 {
            table.selectRowIndexes([0], byExtendingSelection: false)
        }
        view.window?.makeFirstResponder(table)
    }

    private func commit(at row: Int) -> Commit? {
        list.commits.indices.contains(row) ? list.commits[row] : nil
    }

    private func searchSoon() {
        pendingSearch?.cancel()
        pendingSearch = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDelay)
            guard !Task.isCancelled, let self, let scope else { return }
            list.show(scope, search: find.search, isSameSelection: true)
        }
    }

    private func listChanged(_ change: HistoryList.Change) {
        switch change {
        case let .replaced(previous):
            showReplacement(of: previous)
        case .appended:
            table.noteNumberOfRowsChanged()
        case .state:
            break
        }
        updatePlaceholder()
    }

    /// The selected commit stays selected when it's in the history read again, such as after a new
    /// commit arrives, and the detail column empties when it isn't. The row at the top stays at the
    /// top when it's still there, so a refresh doesn't move the list under the user.
    private func showReplacement(of previous: [Commit]) {
        let topRow = table.rows(in: table.visibleRect).location
        let topHash = previous.indices.contains(topRow) ? previous[topRow].hash : nil
        let selected = selectedCommit.flatMap { list.index(of: $0.hash) }
        isRestoringSelection = true
        table.reloadData()
        table.selectRowIndexes(selected.map { IndexSet(integer: $0) } ?? [], byExtendingSelection: false)
        isRestoringSelection = false

        if let top = topHash.flatMap(list.index(of:)) {
            table.scroll(NSPoint(x: 0, y: table.rect(ofRow: top).minY))
        } else if let selected {
            table.scrollRowToVisible(selected)
        } else if table.numberOfRows > 0 {
            table.scrollRowToVisible(0)
        }

        if let selected {
            selectedCommit = list.commits[selected]
        } else if selectedCommit != nil {
            selectedCommit = nil
            onSelect?(nil)
        }
    }

    private func updatePlaceholder() {
        let state: HistoryPlaceholder.State = if let failure = list.failure {
            .failed(summary: failure.summary)
        } else if !list.commits.isEmpty {
            .hidden
        } else if list.isLoading || list.scope == nil {
            .loading
        } else if let search = list.search {
            .noMatches(search.text)
        } else {
            .noCommits
        }
        placeholder.state = state
        placeholderView.isHidden = state == .hidden
    }

    private func putOnPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func focusFind(searching field: HistorySearch.Field?) {
        if let field {
            find.setSearchField(field)
        }
        focusFind()
    }

    /// Edit > Copy with the list focused copies the selected commit's hash.
    @objc func copy(_: Any?) {
        copyCommitHash(nil)
    }

    @objc func copyCommitHash(_: Any?) {
        guard let selectedCommit else { return }
        putOnPasteboard(selectedCommit.hash)
    }

    @objc func copyCommitSubject(_: Any?) {
        guard let selectedCommit else { return }
        putOnPasteboard(selectedCommit.subject)
    }

    @objc func findInHistory(_: Any?) {
        focusFind(searching: nil)
    }

    @objc func findByMessage(_: Any?) {
        focusFind(searching: .message)
    }

    @objc func findByAuthor(_: Any?) {
        focusFind(searching: .author)
    }

    @objc func findInChanges(_: Any?) {
        focusFind(searching: .changes)
    }
}

extension HistoryViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)), #selector(copyCommitHash(_:)), #selector(copyCommitSubject(_:)):
            return selectedCommit != nil
        case #selector(findByMessage(_:)):
            menuItem.state = find.searchField == .message ? .on : .off
        case #selector(findByAuthor(_:)):
            menuItem.state = find.searchField == .author ? .on : .off
        case #selector(findInChanges(_:)):
            menuItem.state = find.searchField == .changes ? .on : .off
        default:
            break
        }
        return true
    }
}

extension HistoryViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in _: NSTableView) -> Int {
        list.commits.count
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard let commit = commit(at: row) else { return nil }
        let view = tableView.makeView(withIdentifier: HistoryRowView.identifier, owner: nil) as? HistoryRowView ?? HistoryRowView()
        view.show(commit, graphRow: list.graph.indices.contains(row) ? list.graph[row] : nil, labels: labels[commit.hash] ?? [])
        list.loadMore(near: row)
        return view
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isRestoringSelection else { return }
        goingToCommit?.cancel()
        let commit = commit(at: table.selectedRow)
        guard commit?.hash != selectedCommit?.hash else { return }
        selectedCommit = commit
        onSelect?(commit)
    }
}
