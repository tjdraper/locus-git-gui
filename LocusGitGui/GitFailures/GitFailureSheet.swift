import SwiftUI

/// What failed in a sentence, Git's own output in full, and for a failure the app recognizes, an
/// explanation and the likely next step.
struct GitFailureSheet: View {
    let failure: GitFailure
    let repository: Repository
    /// Runs the command again. Nil when there’s nothing sensible to repeat.
    let retry: (() -> Void)?
    /// Opened by the user from the toolbar warning, rather than raised by a failed command. The
    /// user closes what they opened with Done, and acknowledges an alert with OK.
    let wasOpenedByUser: Bool
    let dismiss: () -> Void

    @State private var lockState: GitLockRecovery.State?
    @State private var lockRemovalFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.yellow)
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
        switch failure.recognized {
        case let .lockExists(lock):
            Text("""
            Git keeps \(displayPath(lock)) while it changes the repository, so two commands can’t \
            change it at once. Another Git process is working here, or one stopped without \
            cleaning up.
            """)
            lockStatus
        case .accessDenied:
            Text("""
            macOS is keeping Locus Git Gui out of this folder. Allow access under Files & Folders \
            in Privacy & Security settings, then try again.
            """)
        case nil:
            Text("Git couldn’t finish. Its output below says why.")
                .foregroundStyle(.secondary)
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

    /// As tall as Git's output, and scrolling once it is taller than the most the sheet should
    /// take up. Fixing the capped frame at its ideal height is what makes the scroll view fit its
    /// content instead of collapsing.
    private var outputBox: some View {
        ScrollView {
            outputText
        }
        .frame(maxHeight: 240)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
    }

    private var outputText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("$ \(failure.commandLine)")
                .foregroundStyle(.secondary)
            Text(failure.output.isEmpty ? "Git printed nothing, and exited with status \(failure.result.status)." : failure.output)
        }
        .font(.system(.callout, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .fixedSize(horizontal: false, vertical: true)
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

    /// Relative to the repository when it's inside, which is nearly always.
    private func displayPath(_ url: URL) -> String {
        let root = repository.workTree.path.hasSuffix("/") ? repository.workTree.path : repository.workTree.path + "/"
        if url.path.hasPrefix(root) {
            return "“\(url.path.dropFirst(root.count))”"
        }
        return "“\((url.path as NSString).abbreviatingWithTildeInPath)”"
    }
}
