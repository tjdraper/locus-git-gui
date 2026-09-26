import AppKit

/// The window's third column, which shows either the commit selected in the history or the
/// working area. Both stay loaded, so going back and forth keeps each one's place.
final class DetailColumnController: NSViewController {
    let commit: CommitDetailViewController
    let workingArea: WorkingAreaViewController
    private(set) var showsWorkingArea = false

    init(commit: CommitDetailViewController, workingArea: WorkingAreaViewController) {
        self.commit = commit
        self.workingArea = workingArea
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        let view = NSView()
        for child in [commit, workingArea] {
            addChild(child)
            child.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child.view)
            NSLayoutConstraint.activate([
                child.view.topAnchor.constraint(equalTo: view.topAnchor),
                child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        self.view = view
        showWorkingArea(showsWorkingArea)
    }

    func showWorkingArea(_ isShown: Bool) {
        showsWorkingArea = isShown
        guard isViewLoaded else { return }
        workingArea.view.isHidden = !isShown
        commit.view.isHidden = isShown
        workingArea.setShown(isShown)
    }

    /// The diff in view, which the menu bar's diff commands act on.
    var diff: DiffViewController {
        showsWorkingArea ? workingArea.diff : commit.diff
    }
}
