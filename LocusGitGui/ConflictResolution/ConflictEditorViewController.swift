import AppKit
import SwiftUI

/// The conflict window's right-hand side for the file picked in its list. A conflict in the file's
/// lines shows each side's version above the result, with the bar that takes a side between them; a
/// conflict about the file as a whole shows the versions to choose between. An operation stopped
/// partway keeps its bar at the top, with Continue for once every file is resolved.
final class ConflictEditorViewController: NSViewController {
    private static let placingHeight: CGFloat = 300

    let state = ConflictEditorState()
    let result = ConflictResultEditor()
    /// When the result gains or loses edits the file doesn't have yet.
    var onEditedChange: ((Bool) -> Void)?
    private let sides = ConflictSidePanes()
    private let operationStatus: OperationStatus
    private let paneSplit = NSSplitView()
    private let sideSplit = NSSplitView()
    private lazy var modeView = NSHostingView(rootView: ConflictModeView(state: state))
    private var shownMarkers: ConflictMarkers?
    private var hasPlacedResult = false
    private var sharedWidth: CGFloat = 0

    init(operationStatus: OperationStatus) {
        self.operationStatus = operationStatus
        super.init(nibName: nil, bundle: nil)
        state.goToConflict = { [weak self] offset in
            self?.focusResult()
            self?.result.goToConflict(offset: offset)
        }
        state.take = { [weak self] choice in
            self?.focusResult()
            self?.take(choice)
        }
        result.onChange = { [weak self] in self?.resultChanged() }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        let operationBar = HeightForWidthHostingView(rootView: OperationBar(status: operationStatus))
        operationBar.sizingOptions = [.intrinsicContentSize]
        let editorBar = HeightForWidthHostingView(rootView: ConflictEditorBar(state: state))
        editorBar.sizingOptions = [.intrinsicContentSize]
        // As tall as their content, with the panes taking the rest.
        for bar in [operationBar, editorBar] {
            bar.setContentHuggingPriority(.required, for: .vertical)
            bar.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        modeView.sizingOptions = []

        sideSplit.isVertical = true
        sideSplit.dividerStyle = .thin
        sideSplit.addArrangedSubview(sides.ours)
        sideSplit.addArrangedSubview(sides.theirs)

        paneSplit.isVertical = false
        paneSplit.dividerStyle = .thin
        paneSplit.addArrangedSubview(sideSplit)
        paneSplit.addArrangedSubview(makeResultArea(below: editorBar))

        let view = NSView()
        for subview in [operationBar, paneSplit, modeView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            operationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            operationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            operationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            paneSplit.topAnchor.constraint(equalTo: operationBar.bottomAnchor),
            paneSplit.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            paneSplit.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            paneSplit.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            modeView.topAnchor.constraint(equalTo: paneSplit.topAnchor),
            modeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            modeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            modeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.view = view
        showMode()
    }

    /// The result, under the bar that takes a side.
    private func makeResultArea(below editorBar: NSView) -> NSView {
        let resultArea = NSView()
        let separator = NSBox()
        separator.boxType = .separator
        for subview in [editorBar, separator, result.pane] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            resultArea.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            editorBar.topAnchor.constraint(equalTo: resultArea.topAnchor),
            editorBar.leadingAnchor.constraint(equalTo: resultArea.leadingAnchor),
            editorBar.trailingAnchor.constraint(equalTo: resultArea.trailingAnchor),
            separator.topAnchor.constraint(equalTo: editorBar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: resultArea.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: resultArea.trailingAnchor),
            result.pane.topAnchor.constraint(equalTo: separator.bottomAnchor),
            result.pane.leadingAnchor.constraint(equalTo: resultArea.leadingAnchor),
            result.pane.trailingAnchor.constraint(equalTo: resultArea.trailingAnchor),
            result.pane.bottomAnchor.constraint(equalTo: resultArea.bottomAnchor),
        ])
        return resultArea
    }

    /// The result gets a little more than half the height once the window has its size, since the
    /// view is laid out at a smaller one first. The versions share the width equally whenever it
    /// changes. Both wait for the layout pass to finish, which would otherwise undo them.
    override func viewDidLayout() {
        super.viewDidLayout()
        guard !paneSplit.isHidden else { return }
        if !hasPlacedResult, paneSplit.bounds.height >= Self.placingHeight {
            hasPlacedResult = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                paneSplit.setPosition((paneSplit.bounds.height * 0.45).rounded(), ofDividerAt: 0)
                result.scrollToCurrent()
            }
        }
        if sideSplit.bounds.width != sharedWidth {
            sharedWidth = sideSplit.bounds.width
            DispatchQueue.main.async { [weak self] in self?.shareSideWidths() }
        }
    }

    private func shareSideWidths() {
        defer { sides.scrollToCurrent() }
        let count = CGFloat(sideSplit.arrangedSubviews.count)
        let divider = sideSplit.dividerThickness
        let share = (sideSplit.bounds.width - divider * (count - 1)) / count
        for index in 0 ..< sideSplit.arrangedSubviews.count - 1 {
            let position = share * CGFloat(index + 1) + divider * CGFloat(index)
            sideSplit.setPosition(position.rounded(), ofDividerAt: index)
        }
    }

    func showMessage(_ message: String) {
        state.mode = .empty(message)
        showMode()
    }

    func showReading() {
        state.mode = .reading
        showMode()
    }

    func showFailure(_ message: String) {
        state.mode = .failed(message)
        showMode()
    }

    /// `markers` are the conflicts in the file as it was read.
    func show(_ contents: ConflictFileContents, markers: ConflictMarkers, names: ConflictSideNames) {
        state.names = names
        guard contents.isEditable, let text = contents.result.text else {
            state.mode = .choosing(ConflictVersionOptions(contents, names: names))
            state.hasBase = false
            showMode()
            return
        }
        state.mode = .editing
        state.hasBase = contents.base != .absent
        sides.load(contents, names: names)
        showMode()
        shownMarkers = nil
        result.load(text, markers: markers, markerSize: contents.markerSize)
        setBaseShown(state.showsBase)
    }

    /// The file changed on disk while it had no edits here.
    func reload(_ text: String) {
        result.reload(text)
    }

    /// Between the two sides, as the version both started from.
    func setBaseShown(_ isShown: Bool) {
        state.showsBase = isShown
        let isVisible = isShown && state.mode == .editing
        guard sideSplit.arrangedSubviews.contains(sides.base) != isVisible else { return }
        if isVisible {
            sideSplit.insertArrangedSubview(sides.base, at: 1)
        } else {
            sideSplit.removeArrangedSubview(sides.base)
            sides.base.removeFromSuperview()
        }
        sideSplit.adjustSubviews()
        shareSideWidths()
        sharedWidth = sideSplit.bounds.width
    }

    /// Laid out again when the panes appear, which places them the first time.
    private func showMode() {
        let isEditing = state.mode == .editing
        if isEditing, paneSplit.isHidden {
            view.needsLayout = true
        }
        paneSplit.isHidden = !isEditing
        modeView.isHidden = isEditing
    }

    private func take(_ choice: ConflictMarkers.Choice) {
        let name = switch choice {
        case .ours: state.takeOursTitle
        case .theirs: state.takeTheirsTitle
        case .oursThenTheirs: ConflictEditorState.takeBothTitle
        }
        result.take(choice, actionName: name)
    }

    private func resultChanged() {
        let markers = result.markers
        let current = result.currentConflict
        if state.isEdited != result.isEdited {
            state.isEdited = result.isEdited
            onEditedChange?(result.isEdited)
        }
        state.conflictCount = markers.conflicts.count
        state.current = current
        if markers != shownMarkers {
            shownMarkers = markers
            sides.locate(markers, in: result.text, current: current)
        } else {
            sides.show(current: current)
        }
    }

    /// Where a side taken can be undone and edited further. The file list keeps Undo for itself
    /// while it has focus.
    func focusResult() {
        guard state.mode == .editing else { return }
        view.window?.makeFirstResponder(result.textView)
    }
}

/// The versions to choose between, or a message, in place of the panes.
private struct ConflictModeView: View {
    let state: ConflictEditorState

    var body: some View {
        if case let .choosing(options) = state.mode {
            ConflictVersionChoiceView(options: options) { choice in state.choose?(choice) }
        } else {
            ConflictMessageView(state: state)
        }
    }
}
