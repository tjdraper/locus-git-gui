import AppKit

/// The window's middle column: the history, kept below the toolbar.
final class HistoryColumnController: NSViewController {
    let history: HistoryViewController

    init(history: HistoryViewController) {
        self.history = history
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        let view = NSView()
        addChild(history)
        history.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(history.view)
        NSLayoutConstraint.activate([
            history.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            history.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            history.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            history.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.view = view
    }
}
