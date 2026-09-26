import AppKit

/// Says why Go to Parent couldn't take the history to a commit, and offers the commit in a window
/// of its own instead.
enum CommitOutOfReachAlert {
    enum Reason {
        case notInSearch
        case tooFar
        case notInHistory
    }

    static func present(for hash: String, because reason: Reason, on window: NSWindow, open: @escaping () -> Void) {
        let short = String(hash.prefix(7))
        let alert = NSAlert()
        switch reason {
        case .notInSearch:
            alert.messageText = "\(short) isn’t in this search’s results"
            alert.informativeText = "Clear the search to find it in the history, or open it in a window of its own."
        case .tooFar:
            let limit = HistoryList.farthestFind.formatted()
            alert.messageText = "\(short) is more than \(limit) commits down this history"
            alert.informativeText = "Locus Git Gui stops reading there rather than hold that much history. "
                + "You can open the commit in a window of its own."
        case .notInHistory:
            alert.messageText = "\(short) isn’t in this history"
            alert.informativeText = "You can open the commit in a window of its own."
        }
        alert.addButton(withTitle: AppCommand.openCommitInNewWindow.title)
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                open()
            }
        }
    }
}
