import AppKit
import SwiftUI

/// The review window's right column: the file picked, or the review's comments.
final class ReviewDetailViewController: NSViewController {
    private let diff: DiffViewController
    private let overview: NSViewController

    init(diff: DiffViewController, overview: some View) {
        self.diff = diff
        let overviewController = NSHostingController(rootView: overview)
        // The column sets the size, not SwiftUI.
        overviewController.sizingOptions = []
        self.overview = overviewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        for child in [diff, overview] {
            addChild(child)
            child.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child.view)
            NSLayoutConstraint.activate([
                child.view.topAnchor.constraint(equalTo: view.topAnchor),
                child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }
        overview.view.isHidden = true
    }

    var showsOverview = false {
        didSet {
            _ = view
            overview.view.isHidden = !showsOverview
            diff.view.isHidden = showsOverview
        }
    }
}
