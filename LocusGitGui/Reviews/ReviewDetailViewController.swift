import AppKit
import SwiftUI

/// The review window's right column: the file picked, the review's comments, or what can be done
/// with several files picked at once.
final class ReviewDetailViewController: NSViewController {
    enum Mode {
        case file
        case comments
        case files
    }

    private let diff: DiffViewController
    private let comments: NSViewController
    private let files: NSViewController

    init(diff: DiffViewController, comments: some View, files: some View) {
        self.diff = diff
        self.comments = Self.hosting(comments)
        self.files = Self.hosting(files)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// The column sets the size, not SwiftUI.
    private static func hosting(_ view: some View) -> NSViewController {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        return controller
    }

    override func loadView() {
        view = NSView()
        for child in [diff, comments, files] {
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
        show(.file)
    }

    var mode = Mode.file {
        didSet {
            show(mode)
        }
    }

    private func show(_ mode: Mode) {
        _ = view
        diff.view.isHidden = mode != .file
        comments.view.isHidden = mode != .comments
        files.view.isHidden = mode != .files
    }
}
