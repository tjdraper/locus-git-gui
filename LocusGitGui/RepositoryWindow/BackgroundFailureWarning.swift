import AppKit

/// The toolbar's quiet warning for what the app failed at on its own in one repository, such as a
/// refresh or an automatic fetch, and the details it opens: one failure's sheet, or a list of them.
final class BackgroundFailureWarning {
    /// Tries again what failed, when the user asks from the details.
    var retry: ((BackgroundFailures.Source) -> Void)?
    private var failures = BackgroundFailures()
    private let repository: Repository
    private let sheet: GitFailureSheetPresenter
    private let toolbar: RepositoryToolbar

    init(repository: Repository, sheet: GitFailureSheetPresenter, toolbar: RepositoryToolbar) {
        self.repository = repository
        self.sheet = sheet
        self.toolbar = toolbar
    }

    func report(_ failure: GitFailure, from source: BackgroundFailures.Source) {
        failures.set(failure, for: source)
        show()
    }

    func clear(_ source: BackgroundFailures.Source) {
        guard failures.clear(source) else { return }
        show()
    }

    func showDetails(on window: NSWindow?) {
        guard let window else { return }
        let sources = failures.sources
        if let only = sources.first, sources.count == 1, let failure = failures.failure(from: only) {
            sheet.present(failure, repository: repository, on: window, wasOpenedByUser: true) { [weak self] in
                self?.retry?(only)
            }
        } else if !sources.isEmpty {
            sheet.present(failures.all, repository: repository, on: window) { [weak self] in
                for source in sources {
                    self?.retry?(source)
                }
            }
        }
    }

    private func show() {
        guard let first = failures.all.first else {
            toolbar.hideWarning()
            return
        }
        toolbar.showWarning(first.summary, count: failures.all.count)
    }
}
