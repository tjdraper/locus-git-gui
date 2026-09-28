import Foundation

/// Whether the app is running Git in a repository, for the spinner in the toolbar's status. It
/// turns on the moment a command starts and off only once none has run for a moment, so a burst of
/// quick commands, such as a refresh, reads as one rather than flickering.
@Observable
final class GitActivity {
    private static let lingering: Duration = .milliseconds(500)

    private(set) var isWorking = false
    @ObservationIgnored private let log: GitCommandLog
    @ObservationIgnored private var pendingStop: Task<Void, Never>?

    init(log: GitCommandLog) {
        self.log = log
        isWorking = !log.running.isEmpty
        follow()
    }

    private func update() {
        if log.running.isEmpty {
            guard pendingStop == nil, isWorking else { return }
            pendingStop = Task { [weak self] in
                try? await Task.sleep(for: Self.lingering)
                guard !Task.isCancelled, let self else { return }
                pendingStop = nil
                isWorking = false
            }
        } else {
            pendingStop?.cancel()
            pendingStop = nil
            if !isWorking {
                isWorking = true
            }
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
