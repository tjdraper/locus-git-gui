import AppKit
import os

/// A diff of any number of files: a commit's changes in the detail column or a commit window, or
/// one file's in a file window. Side by side when there's room for both versions, and inline when
/// there isn't, unless Settings asks for one of them always. Where the changes come from is up to
/// whoever shows them, through `readFile` and `readImage`.
final class DiffViewController: NSViewController {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "DiffView")

    /// Reads a file's changes whatever their size, for changes that were left out.
    var readFile: ((DiffFile) async throws -> DiffFile)? {
        get { leftOut.read }
        set { leftOut.read = newValue }
    }

    var readImage: ((DiffFile, _ isNew: Bool) async throws -> (data: Data?, byteCount: Int)?)? {
        get { images.read }
        set { images.read = newValue }
    }

    var openFileWindow: ((DiffFile) -> Void)?
    var showFailure: ((GitFailure, _ retry: @escaping () -> Void) -> Void)?
    /// Whether a file window can be opened from here, which a file window itself can't.
    var opensFileWindows = true
    /// The bar above the files, which a diff of one file has no need for.
    var showsSummary = true {
        didSet { updateSummary() }
    }

    /// A control at the start of the bar above the files, which keeps the bar shown with no files.
    var summaryAccessory: NSView? {
        didSet {
            summaryBar.accessory = summaryAccessory
            updateSummary()
        }
    }
    /// Where Next File and Previous File go when the files are somewhere other than this diff, as in
    /// a file window, which shows one of a commit's files at a time.
    var adjacentFiles: AdjacentFiles?

    struct AdjacentFiles {
        let canGo: (_ offset: Int) -> Bool
        let move: (_ offset: Int) -> Void
    }

    /// The heading of each group in a grouped diff, such as the working area's staged changes.
    var describeGroup: ((_ group: Int) -> (title: String, actions: [DiffAction]))?
    /// What can be done to a file, shown in its header and at the top of its menu.
    var fileActions: ((DiffFile) -> [DiffAction])?
    /// What can be done to a hunk, or to the lines of it that are selected, shown on its band. Nil
    /// for a diff whose hunks have nothing to do. `lines` are the selected lines' indices in the
    /// hunk, and empty when none are.
    var hunkActions: ((DiffFile, _ hunk: Int, _ lines: [Int]) -> [DiffAction])? {
        didSet { connectHunkBars() }
    }

    /// Marks the file the keyboard and the menu bar's file commands act on while the diff has focus.
    /// A diff of one file has no need to.
    var highlightsCurrentFile = true
    /// A key typed while the diff has focus, for whoever shows it to use first, as the working area
    /// uses Space. True when it was used.
    var onTypedKey: ((String) -> Bool)?
    /// The file Next File and Previous File went to, which stays current while it's in view.
    var markedFile: DiffFile.Identity? {
        didSet { if markedFile != oldValue { placeDidChange() } }
    }
    /// Whether files can be picked to act on together, with ⌘-click, Shift-click and Shift-J/K.
    var selectsFiles = false
    /// The files picked, in no order. Empty when the current file is the one acted on.
    var selectedFiles: Set<DiffFile.Identity> = [] {
        didSet { if selectedFiles != oldValue { placeDidChange() } }
    }
    /// Where Shift-click and Shift-J/K take in a range from.
    var selectionAnchor: DiffFile.Identity? {
        didSet { if selectionAnchor != oldValue { placeDidChange() } }
    }

    let options: DiffOptionsStore
    let workTree: URL
    let canvas = DiffCanvasView()
    private let scrollView = NSScrollView()
    private let clipView = DiffClipView()
    private(set) lazy var blockViews = DiffBlockViews(canvas: canvas)
    let images = DiffImageStore()
    let leftOut = LeftOutChangesReader()
    private let emptyMessage = NSTextField(labelWithString: "")
    private let summaryBar = DiffSummaryBar()
    private lazy var summaryHeight = summaryBar.heightAnchor.constraint(equalToConstant: 0)
    private var appearance = DiffAppearance()
    private var appearanceWatch: NotificationWatch?

    private(set) var files: [DiffFile] = []
    var collapsedFiles: Set<DiffFile.Identity> = [] {
        didSet { if collapsedFiles != oldValue { placeDidChange() } }
    }
    /// Told a moment after the diff's place changes, for whoever shows it to remember, and at once
    /// before it shows other files.
    var onPlaceChange: ((DiffPlace) -> Void)?
    var reportingPlace: Task<Void, Never>?
    /// Where a diff just shown was left, until it's been laid out and can be scrolled there.
    var pendingScroll: DiffScrollAnchor?
    /// Files whose left-out changes the user asked to see, which whoever reads the diff again, as
    /// the working area does on every refresh, reads whole again.
    private(set) var filesShownWhole: Set<DiffFile.Identity> = []
    private var numberColumns = 3
    private var shownWidth = 0.0
    private var workingTreePresence: [String: Bool] = [:]

    init(options: DiffOptionsStore, workTree: URL) {
        self.options = options
        self.workTree = workTree
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// What Tab moves focus to, which is nothing while there are no changes.
    var focusableView: NSView? {
        files.isEmpty ? nil : canvas
    }

    override func loadView() {
        let view = NSView()
        scrollView.contentView = clipView
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.backgroundColor = .textBackgroundColor
        clipView.onScroll = { [weak self] in
            self?.forgetMarkedFileOutOfView()
            self?.blockViews.update()
            self?.placeDidChange()
        }
        canvas.onTypedKey = { [weak self] key in self?.typed(key) ?? false }
        canvas.onCancel = { [weak self] in self?.clearFileSelection() }
        images.onLoad = { [weak self] in self?.blockViews.update() }
        canvas.setAccessibilityLabel("Changes")
        canvas.setAccessibilityRole(.textArea)
        canvas.makeMenu = { [weak self] file in
            guard let self, let file else { return nil }
            let copies = canvas.selection.map { !$0.isEmpty } ?? false
            return menu(forFile: file).make(copying: copies ? canvas : nil)
        }
        emptyMessage.textColor = .secondaryLabelColor
        emptyMessage.alignment = .center
        emptyMessage.isHidden = true
        connectBlockViews()
        followAppearance()
        summaryBar.onCollapseAll = { [weak self] in self?.collapseAllFiles(nil) }
        summaryBar.onExpandAll = { [weak self] in self?.expandAllFiles(nil) }
        for subview in [summaryBar, scrollView, emptyMessage] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            summaryBar.topAnchor.constraint(equalTo: view.topAnchor),
            summaryBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            summaryBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            summaryHeight,
            scrollView.topAnchor.constraint(equalTo: summaryBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyMessage.topAnchor.constraint(equalTo: summaryBar.bottomAnchor, constant: 24),
            emptyMessage.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            emptyMessage.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        self.view = view
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard abs(clipView.bounds.width - shownWidth) >= 0.5 else { return }
        rebuild(keepingPlace: true)
    }

    /// `isSameDiff` keeps which files are collapsed and where the diff is scrolled to, for the same
    /// changes read again, such as with other options. Otherwise the diff starts out where `place`
    /// says it was left.
    func show(_ files: [DiffFile], emptyMessage message: String, isSameDiff: Bool, place: DiffPlace = DiffPlace()) {
        _ = view
        if !isSameDiff {
            reportPlaceNow()
            collapsedFiles = place.collapsed
            pendingScroll = files.isEmpty ? nil : place.scroll
            filesShownWhole = []
            images.removeAll()
        }
        workingTreePresence = [:]
        leftOut.cancelAll()
        let previousFiles = self.files
        self.files = files
        if isSameDiff {
            markedFile = DiffCommandTarget.markedFile(markedFile, from: previousFiles, in: files)
        } else {
            markedFile = place.marked.flatMap { marked in files.contains { $0.id == marked } ? marked : nil }
            selectedFiles = place.picked
            selectionAnchor = place.pickAnchor
        }
        keepSelectedFilesStillShown()
        numberColumns = DiffLayout.numberColumns(of: files)
        emptyMessage.stringValue = message
        emptyMessage.isHidden = !files.isEmpty
        blockViews.removeAll()
        rebuild(keepingPlace: isSameDiff)
        if isSameDiff {
            scrollToMarkedFileIfOutOfView()
        } else if place.scroll == nil {
            canvas.scroll(to: 0)
        }
    }

    /// For images that may have changed while their file's diff didn't, such as a working tree file.
    func readImagesAgain() {
        for file in files where file.changed.isImage {
            images.readAgain(file)
        }
    }

    func clear() {
        show([], emptyMessage: "", isSameDiff: false)
    }

    func focus() {
        view.window?.makeFirstResponder(focusableView)
    }

    /// Builds the rows again and lays them out at the current width. `keepingPlace` keeps the row
    /// at the top where it was.
    func rebuild(keepingPlace: Bool) {
        updateSummary()
        let width = clipView.bounds.width
        shownWidth = width
        let anchor = keepingPlace ? canvas.content.flatMap { content in
            DiffScrollAnchor(top: canvas.visibleRect.minY, document: content.document, layout: content.layout, files: content.files)
        } : nil
        guard !files.isEmpty, width > 0 else {
            canvas.show(nil, keepingSelection: false)
            canvas.frame = NSRect(x: 0, y: 0, width: max(width, 0), height: 0)
            blockViews.update()
            return
        }
        let started = ContinuousClock.now
        let metrics = appearance.metrics
        let style = DiffLayout.style(forWidth: width, metrics: metrics, numberColumns: numberColumns, layout: appearance.layout)
        let collapsed = Set(files.indices.filter { collapsedFiles.contains(files[$0].id) })
        let document = DiffDocument(files: files, collapsed: collapsed, style: style, headsGroups: describeGroup != nil)
        let layout = DiffLayout(document: document, files: files, metrics: metrics, width: width, numberColumns: numberColumns)
        let isSameShape = canvas.content.map { $0.document == document } ?? false
        canvas.show(
            DiffCanvasView.Content(
                files: files, document: document, layout: layout, painter: appearance.painter, tintsHunkBands: hunkActions == nil
            ),
            keepingSelection: isSameShape
        )
        canvas.frame = NSRect(x: 0, y: 0, width: width, height: layout.height)
        if !isSameShape {
            blockViews.removeAll()
        }
        if let pendingScroll, let top = pendingScroll.top(in: document, layout: layout, files: files) {
            self.pendingScroll = nil
            canvas.scroll(to: top)
        } else if let top = anchor?.top(in: document, layout: layout, files: files) {
            canvas.scroll(to: top)
        }
        blockViews.update()
        let elapsed = ContinuousClock.now - started
        Self.log.info("Laid out \(document.blocks.count) rows in \(elapsed, privacy: .public)")
    }

    private func updateSummary() {
        guard isViewLoaded else { return }
        summaryBar.show(files: files, isAllCollapsed: files.allSatisfy { collapsedFiles.contains($0.id) })
        let isShown = showsSummary && (!files.isEmpty || summaryAccessory != nil)
        summaryBar.isHidden = !isShown
        summaryHeight.constant = isShown ? summaryBar.height : 0
    }

    func index(of id: DiffFile.Identity) -> Int? {
        files.firstIndex { $0.id == id }
    }

    /// Reads a file's left-out changes, or tries again after a failure.
    func showChanges(ofFile id: DiffFile.Identity) {
        guard leftOut.canRead, let index = index(of: id) else { return }
        filesShownWhole.insert(id)
        files[index].reading = .reading
        rebuild(keepingPlace: true)
        leftOut.start(files[index]) { [weak self] result in
            guard let self, let index = self.index(of: id) else { return }
            switch result {
            case let .success(file):
                files[index] = file
                numberColumns = DiffLayout.numberColumns(of: files)
            case let .failure(failed):
                files[index].reading = .failed(summary: failed.summary)
            }
            rebuild(keepingPlace: true)
        }
    }
}

/// Settings' font and layout, which every diff shown follows as they change.
private extension DiffViewController {
    func followAppearance() {
        appearanceWatch = NotificationWatch(DiffPreferences.didChange) { [weak self] in
            self?.appearanceDidChange()
        }
    }

    func appearanceDidChange() {
        let appearance = DiffAppearance()
        guard appearance.differs(from: self.appearance) else { return }
        self.appearance = appearance
        rebuild(keepingPlace: true)
    }
}

/// What can be done with one file in the diff, from its header, its menu or the menu bar.
extension DiffViewController {
    var commandTarget: DiffCommandTarget? {
        guard let content = canvas.content else { return nil }
        return DiffCommandTarget(
            document: content.document,
            layout: content.layout,
            selection: canvas.selection,
            visibleTop: canvas.visibleRect.minY + content.layout.metrics.headerHeight,
            visibleBottom: canvas.visibleRect.maxY,
            markedFile: markedFile.flatMap(index(of:))
        )
    }

    func isInWorkingTree(_ path: String) -> Bool {
        if let known = workingTreePresence[path] {
            return known
        }
        let exists = WorkingTreeFile(path: path, in: workTree).exists
        workingTreePresence[path] = exists
        return exists
    }

    func openInEditor(path: String) {
        let file = WorkingTreeFile(path: path, in: workTree)
        guard file.exists else {
            NSSound.beep()
            return
        }
        file.openInEditor()
    }

    func openFileWindow(_ id: DiffFile.Identity) {
        guard opensFileWindows, let index = index(of: id) else { return }
        openFileWindow?(files[index])
    }

    func menu(forFile index: Int) -> ChangedFileMenu {
        let id = files[index].id
        let path = id.path
        let file = WorkingTreeFile(path: path, in: workTree)
        return ChangedFileMenu(
            actions: fileActions?(files[index]) ?? [],
            isInWorkingTree: isInWorkingTree(path),
            opensFileWindows: opensFileWindows,
            isCollapsed: collapsedFiles.contains(id),
            openInEditor: { [weak self] in self?.openInEditor(path: path) },
            revealInFinder: file.revealInFinder,
            copyAbsolutePath: file.copyAbsolutePath,
            copyPathFromRepositoryRoot: file.copyPathFromRepositoryRoot,
            openFileWindow: { [weak self] in self?.openFileWindow(id) },
            toggleCollapsed: { [weak self] in self?.toggleCollapsed(id) }
        )
    }
}

/// Reports every scroll as it happens, so the file headers move with the diff in the same frame
/// rather than a moment after, as they would waiting for a notification. Scrolling from the keyboard
/// and the scroll bar goes through `scroll(to:)` without setting the bounds' origin, and the
/// trackpad sets the origin directly.
private final class DiffClipView: NSClipView {
    var onScroll: (() -> Void)?

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: newOrigin)
        onScroll?()
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(newOrigin)
        onScroll?()
    }
}
