import SwiftUI

/// What failed in a sentence, Git's own output in full, and for a failure the app recognizes, an
/// explanation and the likely next step.
struct GitFailureSheet: View {
    let failure: GitFailure
    let repository: Repository
    /// Runs the command again. Nil when there’s nothing sensible to repeat.
    let retry: (() -> Void)?
    /// What a remote failure offers besides trying again.
    var nextSteps = GitFailureNextSteps()
    /// Opened by the user from the toolbar warning, rather than raised by a failed command. The
    /// user closes what they opened with Done, and acknowledges an alert with OK.
    let wasOpenedByUser: Bool
    let dismiss: () -> Void

    @State private var lockState: GitLockRecovery.State?
    @State private var lockRemovalFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                GitFailureSymbol(failure: failure)
                VStack(alignment: .leading, spacing: 6) {
                    Text(failure.summary)
                        .font(.headline)
                    explanation
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            outputBox
            buttons
        }
        .padding(20)
        .frame(width: 560)
        .task {
            checkLock()
        }
    }

    @ViewBuilder
    private var explanation: some View {
        GitFailureExplanation(failure: failure, repository: repository)
        if case .lockExists = failure.recognized {
            lockStatus
        }
    }

    @ViewBuilder
    private var lockStatus: some View {
        switch lockState {
        case let .inUse(processes):
            Text("""
            A Git process is running in this repository right now (process \
            \(processes.map(String.init).joined(separator: ", "))). Let it finish, then check again.
            """)
            .foregroundStyle(.secondary)
        case let .abandoned(since):
            Text(abandonedDescription(since: since))
                .foregroundStyle(.secondary)
        case .gone:
            Text("The lock is gone now.")
                .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
        if lockRemovalFailed {
            Text("The lock couldn’t be removed.")
                .foregroundStyle(.red)
        }
    }

    private var outputBox: some View {
        GitFailureOutput(failure: failure)
    }

    private var buttons: some View {
        HStack {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(failure.transcript, forType: .string)
            }
            Spacer()
            nextStepButton
            Button(wasOpenedByUser ? "Done" : "OK", action: dismiss)
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var nextStepButton: some View {
        switch (failure.recognized, lockState) {
        case (.lockExists, .inUse?):
            Button("Check Again", action: checkLock)
        case let (.lockExists(lock), .abandoned?):
            Button("Remove Lock") {
                removeLock(lock)
            }
        case (.lockExists, .gone?):
            if let retry {
                Button("Try Again") {
                    dismiss()
                    retry()
                }
            }
        case (.accessDenied, _):
            Button("Open Privacy & Security") {
                PrivacySettings.openFilesAndFolders()
            }
        case (.pushBehindRemote, _):
            if let forcePush = nextSteps.forcePush {
                Button("Force Push…") {
                    dismiss()
                    forcePush()
                }
            }
            if let pull = nextSteps.pull {
                Button("Pull") {
                    dismiss()
                    pull()
                }
            }
        case (.upstreamGone, _):
            if let push = nextSteps.push {
                Button("Push") {
                    dismiss()
                    push()
                }
            }
        case (.pushLeaseStale, _):
            if let fetch = nextSteps.fetch {
                Button("Fetch") {
                    dismiss()
                    fetch()
                }
            }
        case (.authenticationFailed, _), (.unreachable, _):
            if let retry {
                Button("Try Again") {
                    dismiss()
                    retry()
                }
            }
        default:
            EmptyView()
        }
    }

    private func checkLock() {
        guard case let .lockExists(lock) = failure.recognized else { return }
        lockState = GitLockRecovery.state(of: lock, in: repository)
    }

    private func removeLock(_ lock: URL) {
        do {
            try GitLockRecovery.remove(lock, in: repository)
        } catch {
            lockRemovalFailed = true
            checkLock()
            return
        }
        dismiss()
        retry?()
    }

    private func abandonedDescription(since: Date?) -> String {
        let age = since.map { " It was left \($0.formatted(.relative(presentation: .named)))." } ?? ""
        return "No Git process is running in this repository, so nothing is using the lock.\(age) It’s safe to remove."
    }
}
