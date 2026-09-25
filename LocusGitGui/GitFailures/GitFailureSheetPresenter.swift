import AppKit
import SwiftUI

/// Shows a failure as a sheet on the repository's window. A new failure replaces one already showing.
final class GitFailureSheetPresenter {
    private var sheet: NSWindow?

    func present(
        _ failure: GitFailure,
        repository: Repository,
        on window: NSWindow,
        wasOpenedByUser: Bool,
        retry: (() -> Void)?
    ) {
        dismiss()
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: GitFailureSheet(
            failure: failure,
            repository: repository,
            retry: retry,
            wasOpenedByUser: wasOpenedByUser,
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
