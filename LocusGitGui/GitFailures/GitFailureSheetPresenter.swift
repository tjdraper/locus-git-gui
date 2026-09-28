import AppKit
import SwiftUI

/// Shows a failure as a sheet on the repository's window. A new failure replaces one already showing.
final class GitFailureSheetPresenter {
    /// Opens the repository's conflict window and returns it. A command that stopped on conflicts
    /// shows its failure there, and one that found conflicts left, such as Continue, offers Show
    /// Conflicts to open it.
    var conflictWindow: (() -> NSWindow?)?
    private var sheet: NSWindow?

    func present(
        _ failure: GitFailure,
        repository: Repository,
        on window: NSWindow,
        wasOpenedByUser: Bool,
        retry: (() -> Void)?,
        nextSteps: GitFailureNextSteps = GitFailureNextSteps()
    ) {
        var window = window
        var nextSteps = nextSteps
        if failure.recognized?.stopsOnConflicts == true, let conflicts = conflictWindow?() {
            window = conflicts
        } else if let conflictWindow {
            nextSteps.showConflicts = { _ = conflictWindow() }
        }
        dismiss()
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: GitFailureSheet(
            failure: failure,
            repository: repository,
            retry: retry,
            nextSteps: nextSteps,
            wasOpenedByUser: wasOpenedByUser,
            dismiss: { [weak self] in self?.dismiss() }
        )))
        self.sheet = sheet
        window.beginSheet(sheet)
    }

    /// Opened by the user from the toolbar warning, when the app failed at more than one thing.
    func present(_ failures: [GitFailure], repository: Repository, on window: NSWindow, retry: @escaping () -> Void) {
        dismiss()
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: GitFailureListSheet(
            failures: failures,
            repository: repository,
            retry: retry,
            dismiss: { [weak self] in self?.dismiss() }
        )))
        self.sheet = sheet
        window.beginSheet(sheet)
    }

    func dismiss() {
        guard let sheet else { return }
        self.sheet = nil
        sheet.sheetParent?.endSheet(sheet)
    }
}
