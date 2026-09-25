import AppKit

/// Tells the user when the chosen Git can no longer run, once each time it goes missing, and
/// offers the checklist to pick another. The app never switches to a different Git by itself.
final class GitMissingNotice {
    private var reportedURL: URL?

    func update(for availability: GitChoice.Availability, checklistIsVisible: Bool, showChecklist: () -> Void) {
        guard case let .missing(url) = availability else {
            reportedURL = nil
            return
        }
        guard reportedURL != url else { return }
        reportedURL = url
        // The checklist already says so in its Git step.
        guard !checklistIsVisible else { return }

        if askToChooseAnother(missing: url) {
            showChecklist()
        }
    }

    private func askToChooseAnother(missing url: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Locus Git Gui can’t find Git"
        alert.informativeText = """
        The selected Git executable has been moved or uninstalled. Choose another Git executable to keep \
        working.

        Missing path: \((url.path as NSString).abbreviatingWithTildeInPath)
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Choose Git…")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
