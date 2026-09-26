import AppKit

/// A spinner in the repository window's toolbar while the app runs Git there, which opens the
/// Activity window when clicked.
final class ActivityIndicator: NSObject {
    static let identifier = NSToolbarItem.Identifier("Activity")

    /// A burst of quick commands, such as a refresh, would otherwise flicker the spinner on and off.
    private static let lingering: Duration = .milliseconds(500)

    private let log: GitCommandLog
    private let showActivity: () -> Void
    private let spinner = NSProgressIndicator()
    private weak var item: NSToolbarItem?
    private var pendingHide: Task<Void, Never>?

    init(log: GitCommandLog, showActivity: @escaping () -> Void) {
        self.log = log
        self.showActivity = showActivity
        super.init()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        follow()
    }

    func makeItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.identifier)
        item.label = "Activity"
        item.toolTip = "Git is working in this repository. Click to see what it’s doing."
        let button = NSButton(title: "", target: self, action: #selector(clicked(_:)))
        button.isBordered = false
        button.setAccessibilityLabel("Activity")
        button.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(spinner)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28),
            spinner.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        item.view = button
        item.isHidden = log.running.isEmpty
        self.item = item
        update()
        return item
    }

    @objc private func clicked(_: Any?) {
        showActivity()
    }

    /// Shown the moment a command starts, and hidden only once none has run for a moment.
    private func update() {
        if log.running.isEmpty {
            guard pendingHide == nil, item?.isHidden == false else { return }
            pendingHide = Task { [weak self] in
                try? await Task.sleep(for: Self.lingering)
                guard !Task.isCancelled, let self else { return }
                pendingHide = nil
                item?.isHidden = true
                spinner.stopAnimation(nil)
            }
        } else {
            pendingHide?.cancel()
            pendingHide = nil
            item?.isHidden = false
            spinner.startAnimation(nil)
        }
    }

    private func follow() {
        withObservationTracking {
            _ = log.running
        } onChange: { [weak self] in
            // Called before the change is made, so the list is read once it has been.
            Task { @MainActor in
                self?.update()
                self?.follow()
            }
        }
    }
}
