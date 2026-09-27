import Foundation

/// What the bar above the history shows about the repository's own operations: one that stopped
/// partway, with Continue, Skip and Abort, or a notice naming the commit a destructive command left
/// behind, which is how to bring it back.
@Observable
final class OperationStatus {
    struct Notice: Equatable {
        let message: String
        /// Copied by Copy Hash.
        let hash: String
    }

    private(set) var stopped: StoppedOperation?
    private(set) var notice: Notice?

    @ObservationIgnored var continueOperation: (() -> Void)?
    @ObservationIgnored var skip: (() -> Void)?
    @ObservationIgnored var abort: (() -> Void)?

    func show(_ stopped: StoppedOperation?) {
        guard stopped != self.stopped else { return }
        self.stopped = stopped
    }

    func show(_ notice: Notice) {
        self.notice = notice
    }

    func dismissNotice() {
        notice = nil
    }
}
