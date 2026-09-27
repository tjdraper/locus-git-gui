import AppKit

/// The window's middle column: the history, under the bar that shows a fetch, pull or push in
/// progress. The bar takes no room while nothing runs.
final class HistoryColumnController: NSViewController {
    let history: HistoryViewController
    private let bar: NSView

    init(history: HistoryViewController, bar: NSView) {
        self.history = history
        self.bar = bar
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        let view = NSView()
        addChild(history)
        for subview in [bar, history.view] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            history.view.topAnchor.constraint(equalTo: bar.bottomAnchor),
            history.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            history.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            history.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.view = view
    }
}
