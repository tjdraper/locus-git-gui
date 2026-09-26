import AppKit
import SwiftUI

/// The middle column: the history of whatever the sidebar has selected, with Find above it. A table
/// rather than a SwiftUI list, which stops keeping up long before a history of a million commits.
final class HistoryViewController: NSViewController {
    /// Commands the window passes on to the history from whichever column has focus, since they
    /// act on the history wherever the user is.
    static let windowActions: Set<Selector> = [
        #selector(openCommitInNewWindow(_:)),
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
    var onOpen: ((Commit) -> Void)?
    var reveal: ((SidebarItemID) -> Void)?
    var showFailure: ((GitFailure, _ retry: @escaping () -> Void) -> Void)?

    private(set) var selectedCommit: Commit?
    let table = HistoryTableView()
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
        open: { [weak self] hash in self?.open(hash) },
        reveal: { [weak self] id in self?.reveal?(id) }
    )
    private var labels: [String: [CommitRefLabel]] = [:]
    private var scope: HistoryScope?
    /// Selection changes the history makes itself, rather than the user.
    private var isRestoringSelection = false
    private var pendingSearch: Task<Void, Never>?
    private lazy var navigator = HistoryCommitNavigator(list: list, table: table) { [weak self] in
        self?.focusList()
    } open: { [weak self] commit in
        self?.onOpen?(commit)
    }
    private var shownGraphLanes = 0
    /// The selected commit, while a search that may yet find it is still arriving.
    private var pendingSelection: String?

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
        table.target = self
        table.doubleAction = #selector(openClickedCommit(_:))
        table.onReturn = { [weak self] in self?.openCommitInNewWindow(nil) }
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
        reloadVisibleRows()
    }

    private func reloadVisibleRows() {
        shownGraphLanes = list.graphLanes
        let visible = table.rows(in: table.visibleRect)
        guard visible.length > 0 else { return }
        table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location ..< NSMaxRange(visible)), columnIndexes: [0])
    }

    func labels(of commit: Commit) -> [CommitRefLabel] {
        labels[commit.hash] ?? []
    }

    /// Reads on down the history until it reaches the commit, or says why it can't.
    func goToCommit(_ hash: String) {
        navigator.goTo(hash)
    }

    /// A parent's short hash and subject when it's been read, and only its short hash otherwise.
    func title(ofCommit hash: String) -> String {
        let short = String(hash.prefix(7))
        guard let index = list.index(of: hash) else { return short }
        return "\(short)  \(list.commits[index].subject)"
    }

    /// The selected commit's parents, for Go to Parent.
    var parentChoices: [CommandPaletteDestination] {
        CommitPaletteChoices.parents(of: selectedCommit, title: title(ofCommit:)) { [weak self] hash in self?.goToCommit(hash) }
    }

    /// The selected commit's branches and tags, for Reveal in Sidebar.
    var labelChoices: [CommandPaletteDestination] {
        CommitPaletteChoices.labels(selectedCommit.map(labels(of:)) ?? []) { [weak self] item in self?.reveal?(item) }
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

    private func open(_ hash: String) {
        guard let index = list.index(of: hash) else { return }
        onOpen?(list.commits[index])
    }

    @objc private func openClickedCommit(_: Any?) {
        guard let commit = commit(at: table.clickedRow) else { return }
        onOpen?(commit)
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
            showReplacement(sameHistoryAs: previous)
        case let .appended(range):
            let shownRows = table.numberOfRows
            table.noteNumberOfRowsChanged()
            selectPendingCommit()
            // A page further down can reach wider than those before it, which moves every subject.
            if list.graphLanes != shownGraphLanes {
                reloadVisibleRows()
            } else if range.lowerBound < shownRows {
                // The loading row the page's first commit takes the place of.
                table.reloadData(forRowIndexes: [range.lowerBound], columnIndexes: [0])
            }
        case .state:
            // A read that failed partway down takes the loading row away.
            if table.numberOfRows != numberOfRows(in: table) {
                table.noteNumberOfRowsChanged()
            }
            if !list.isLoading, pendingSelection != nil {
                pendingSelection = nil
                selectedCommit = nil
                onSelect?(nil)
            }
        }
        updatePlaceholder()
    }

    /// The selected commit stays selected when it's in the history read again, such as after a new
    /// commit arrives, and the detail column empties when it isn't. When it's the same history, the
    /// row at the top stays at the top, so a refresh doesn't move the list under the user. A
    /// different history, or a search started or cleared, starts at the selection or the top.
    private func showReplacement(sameHistoryAs previous: [Commit]?) {
        let topRow = table.rows(in: table.visibleRect).location
        let topHash = previous.flatMap { $0.indices.contains(topRow) ? $0[topRow].hash : nil }
        let selected = selectedCommit.flatMap { list.index(of: $0.hash) }
        isRestoringSelection = true
        shownGraphLanes = list.graphLanes
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
        } else if let selectedCommit, list.isLoading {
            // A search shows its matches as it finds them, and may find this one yet.
            pendingSelection = selectedCommit.hash
        } else if selectedCommit != nil {
            selectedCommit = nil
            onSelect?(nil)
        }
    }

    private func selectPendingCommit() {
        guard let hash = pendingSelection, let index = list.index(of: hash) else { return }
        pendingSelection = nil
        isRestoringSelection = true
        table.selectRowIndexes([index], byExtendingSelection: false)
        isRestoringSelection = false
    }

    private func updatePlaceholder() {
        placeholder.show(list)
        placeholderView.isHidden = placeholder.state == .hidden
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
}

/// The Commit and Find commands, which reach the history from whichever column has focus.
extension HistoryViewController {
    /// Edit > Copy with the list focused copies the selected commit's hash.
    @objc func copy(_: Any?) {
        copyCommitHash(nil)
    }

    @objc func openCommitInNewWindow(_: Any?) {
        guard let selectedCommit else { return }
        onOpen?(selectedCommit)
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
        case #selector(copy(_:)), #selector(copyCommitHash(_:)), #selector(copyCommitSubject(_:)), #selector(openCommitInNewWindow(_:)):
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
    /// One more row than there are commits while the history has more to read, holding a spinner,
    /// so the end of what's been read never looks like the end of the history.
    func numberOfRows(in _: NSTableView) -> Int {
        list.commits.count + (hasLoadingRow ? 1 : 0)
    }

    private var hasLoadingRow: Bool {
        !list.commits.isEmpty && !list.isComplete && list.failure == nil
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard let commit = commit(at: row) else {
            loadMoreSoon(near: row)
            return tableView.makeView(withIdentifier: HistoryLoadingRowView.identifier, owner: nil) ?? HistoryLoadingRowView()
        }
        let view = tableView.makeView(withIdentifier: HistoryRowView.identifier, owner: nil) as? HistoryRowView ?? HistoryRowView()
        view.show(
            commit,
            graphRow: list.graph.indices.contains(row) ? list.graph[row] : nil,
            graphLanes: list.graphLanes,
            labels: labels[commit.hash] ?? []
        )
        loadMoreSoon(near: row)
        return view
    }

    /// Once the table has finished laying out its rows. Reading the next page changes how many it
    /// has, and a table told that while it's asking for a row's view throws an exception.
    private func loadMoreSoon(near row: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.list.loadMore(near: row)
        }
    }

    func tableView(_: NSTableView, shouldSelectRow row: Int) -> Bool {
        commit(at: row) != nil
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isRestoringSelection else { return }
        navigator.cancel()
        pendingSelection = nil
        let commit = commit(at: table.selectedRow)
        guard commit?.hash != selectedCommit?.hash else { return }
        selectedCommit = commit
        onSelect?(commit)
    }
}
