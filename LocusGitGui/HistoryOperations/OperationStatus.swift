import Foundation

/// What the window's status shows about the repository's own operations: one that stopped
/// partway, with Continue, Skip and Abort, or a notice naming the commit a destructive command left
/// behind, which is how to bring it back.
@Observable
final class OperationStatus {
    struct Notice: Equatable {
        let message: String
        /// Copied by Copy Hash.
        let hash: String
        var shown = Date.now
    }

    private(set) var stopped: StoppedOperation?
    /// When it stopped, as far as this window knows: the toolbar shows the latest of what the window
    /// has to say. A step onward in the same operation, such as a rebase's next stop, keeps it.
    private(set) var stoppedSince: Date?
    private(set) var notice: Notice?

    @ObservationIgnored var continueOperation: (() -> Void)?
    @ObservationIgnored var skip: (() -> Void)?
    @ObservationIgnored var abort: (() -> Void)?

    func show(_ stopped: StoppedOperation?) {
        guard stopped != self.stopped else { return }
        if stopped?.kind != self.stopped?.kind {
            stoppedSince = stopped == nil ? nil : .now
        }
        self.stopped = stopped
    }

    func show(_ notice: Notice) {
        self.notice = notice
    }

    func dismissNotice() {
        notice = nil
    }
}
