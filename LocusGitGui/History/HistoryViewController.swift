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

    /// What the history has selected: the working area, or a commit.
    enum Item: Equatable {
        case workingArea
        case commit(Commit)
    }

    var onSelect: ((Item?) -> Void)?
    var onOpen: ((Commit) -> Void)?
    /// The working area in a window of its own.
    var onOpenWorkingArea: (() -> Void)?
    var reveal: ((SidebarItemID) -> Void)?
    /// Told a moment after the selection or the scrolling changes, and at once before the history
    /// shows another sidebar item's.
    var onPlaceChange: ((HistoryPlace) -> Void)?
    /// Told when the text or field Find in History looks in changes, for the window to remember.
    var onFindChange: (() -> Void)?
    var reportingPlace: Task<Void, Never>?
    /// Where the history being read was left, until it's been read and can be shown there.
    var pendingPlace: HistoryPlace?
    var showFailure: ((GitFailure, _ retry: @escaping () -> Void) -> Void)?

    private(set) var selectedCommit: Commit?
    var isWorkingAreaSelected = false
    /// Nil until the repository's status has been read, and the history has no working area row.
    var workingArea: WorkingAreaSummary?
    let table = HistoryTableView()
    let list: HistoryList
    let scrollView = NSScrollView()
    private(set) lazy var find = HistoryFindField(menuItems: [AppCommand.findByMessage, .findByAuthor, .findInChanges].map { command in
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
    var isRestoringSelection = false
    private var pendingSearch: Task<Void, Never>?
    private(set) lazy var navigator = HistoryCommitNavigator(list: list, table: table) { [weak self] index in
        self?.row(ofCommit: index) ?? index
    } focusList: { [weak self] in
        self?.focusList()
    } open: { [weak self] commit in
        self?.onOpen?(commit)
    }
    private var shownGraphLanes = 0
    /// Moves the placeholder below the working area's row while there is one.
    private lazy var placeholderTop = placeholderView.topAnchor.constraint(equalTo: scrollView.topAnchor)
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
        contextMenu.isWorkingAreaForMenu = { [weak self] in self.map { $0.isWorkingAreaRow($0.table.clickedRow) } ?? false }
        contextMenu.openWorkingArea = { [weak self] in self?.onOpenWorkingArea?() }
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
        find.onChange = { [weak self] in
            self?.searchSoon()
            self?.onFindChange?()
        }
        find.moveToList = { [weak self] in self?.focusList() }
        observeScrolling()

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
            placeholderTop,
            placeholderView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
        ])
        self.view = view
        updatePlaceholder()
    }

    /// Asked on every refresh, and only read again when the commits it starts from have moved.
    /// `place` is where another sidebar item's history was left, to show it there once it's read.
    func show(_ scope: HistoryScope, isSameSelection: Bool, place: HistoryPlace? = nil) {
        if !isSameSelection {
            reportPlaceNow()
            pendingPlace = place
        }
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

    func commit(at row: Int) -> Commit? {
        let index = row - commitRowOffset
        return list.commits.indices.contains(index) ? list.commits[index] : nil
    }

    private func searchSoon() {
        pendingSearch?.cancel()
        pendingSearch = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDelay)
            guard !Task.isCancelled, let self, let scope else { return }
            list.show(scope, search: find.search, isSameSelection: true)
        }
    }

    func updatePlaceholder() {
        placeholder.show(list)
        placeholderView.isHidden = placeholder.state == .hidden
        placeholderTop.constant = workingArea == nil ? 0 : HistoryRowView.height
    }
}

/// Keeping the rows and the selection in step with the history as it's read.
extension HistoryViewController {
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
            } else if row(ofCommit: range.lowerBound) < shownRows {
                // The loading row the page's first commit takes the place of.
                table.reloadData(forRowIndexes: [row(ofCommit: range.lowerBound)], columnIndexes: [0])
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
        if let place = pendingPlace {
            pendingPlace = nil
            isRestoringSelection = true
            shownGraphLanes = list.graphLanes
            table.reloadData()
            isRestoringSelection = false
            show(place)
            return
        }
        let visibleTopRow = table.rows(in: table.visibleRect).location
        let topRow = visibleTopRow - commitRowOffset
        let topHash = previous.flatMap { $0.indices.contains(topRow) ? $0[topRow].hash : nil }
        let selected = selectedCommit.flatMap { list.index(of: $0.hash) }
        let selectedRow = selected.map(row(ofCommit:)) ?? (isWorkingAreaSelected ? 0 : nil)
        isRestoringSelection = true
        shownGraphLanes = list.graphLanes
        table.reloadData()
        table.selectRowIndexes(selectedRow.map { IndexSet(integer: $0) } ?? [], byExtendingSelection: false)
        isRestoringSelection = false

        if previous != nil, workingArea != nil, visibleTopRow == 0 {
            // The working area's row was at the top, and stays there.
            table.scrollRowToVisible(0)
        } else if let top = topHash.flatMap(list.index(of:)) {
            table.scroll(NSPoint(x: 0, y: table.rect(ofRow: row(ofCommit: top)).minY))
        } else if let selectedRow {
            table.scrollRowToVisible(selectedRow)
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
        table.selectRowIndexes([row(ofCommit: index)], byExtendingSelection: false)
        isRestoringSelection = false
    }
}

extension HistoryViewController: NSTableViewDataSource, NSTableViewDelegate {
    /// One more row than there are commits while the history has more to read, holding a spinner,
    /// so the end of what's been read never looks like the end of the history.
    func numberOfRows(in _: NSTableView) -> Int {
        commitRowOffset + list.commits.count + (hasLoadingRow ? 1 : 0)
    }

    private var hasLoadingRow: Bool {
        !list.commits.isEmpty && !list.isComplete && list.failure == nil
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        if isWorkingAreaRow(row), let workingArea {
            let view = tableView.makeView(withIdentifier: WorkingAreaRowView.identifier, owner: nil) as? WorkingAreaRowView
                ?? WorkingAreaRowView()
            let graphWidth = list.search == nil ? CGFloat(max(list.graphLanes, 1)) * CommitGraphView.laneWidth : 0
            view.show(workingArea, graphWidth: graphWidth, graphPadding: HistoryRowView.graphPadding)
            return view
        }
        let index = row - commitRowOffset
        guard let commit = commit(at: row) else {
            loadMoreSoon(near: index)
            return tableView.makeView(withIdentifier: HistoryLoadingRowView.identifier, owner: nil) ?? HistoryLoadingRowView()
        }
        let view = tableView.makeView(withIdentifier: HistoryRowView.identifier, owner: nil) as? HistoryRowView ?? HistoryRowView()
        view.show(
            commit,
            graphRow: list.graph.indices.contains(index) ? list.graph[index] : nil,
            graphLanes: list.graphLanes,
            labels: labels[commit.hash] ?? []
        )
        loadMoreSoon(near: index)
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
        isWorkingAreaRow(row) || commit(at: row) != nil
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isRestoringSelection else { return }
        navigator.cancel()
        pendingSelection = nil
        let isWorkingArea = isWorkingAreaRow(table.selectedRow)
        let commit = commit(at: table.selectedRow)
        guard commit?.hash != selectedCommit?.hash || isWorkingArea != isWorkingAreaSelected else { return }
        selectedCommit = commit
        isWorkingAreaSelected = isWorkingArea
        onSelect?(isWorkingArea ? .workingArea : commit.map(Item.commit))
        placeDidChange()
    }
}
