import AppKit

/// Where buying starts: from Purchase… anywhere, and in place of a command the lock refuses. Buying
/// arrives with the license server; until then this says how long the trial has left, or that it has
/// ended, and what a license unlocks.
enum PurchaseSheet {
    private static var isShown = false

    static func show(on window: NSWindow?, entitlements: EntitlementStore = .shared) {
        // A command repeated from the keyboard would otherwise queue one sheet after another.
        guard !isShown else { return }
        isShown = true
        let alert = NSAlert()
        switch entitlements.notice {
        case let .running(daysLeft):
            alert.messageText = daysLeft == 1 ? "1 day left in your trial" : "\(daysLeft) days left in your trial"
            alert.informativeText = """
            Everything works until then. After the trial, Locus Git Gui still opens your repositories \
            and shows their history, changes, and status. Changing a repository, talking to a \
            remote, or using reviews needs a license.
            """
        case .ended:
            alert.messageText = "Your trial has ended"
            alert.informativeText = """
            Locus Git Gui still opens your repositories and shows their history, changes, and status. \
            Changing a repository, talking to a remote, or using reviews needs a license.
            """
        case nil:
            // Only for the moment at launch before the trial's start has been read.
            alert.messageText = "Purchase Locus Git Gui"
            alert.informativeText = "After the trial, changing a repository, talking to a remote, or using reviews needs a license."
        }
        alert.addButton(withTitle: "OK")
        Task {
            _ = await AlertPresentation.run(alert, on: window)
            isShown = false
        }
    }
}
