import SwiftUI

/// Says when Git runs without the login shell's environment, which is why a hook or signing that
/// works in Terminal would fail here.
struct ShellEnvironmentNotice: View {
    let fallback: LoginShellEnvironment.Fallback

    var body: some View {
        Label {
            Text("Git is running without your shell’s settings")
            Text("""
            \(reason) So Git runs with the environment Locus Git Gui was opened with, and hooks or \
            signing may not find programs your shell adds to the PATH. Check your shell’s startup \
            files, then quit and reopen Locus Git Gui.
            """)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
    }

    private var shellName: String {
        LoginShellEnvironment.userShell().lastPathComponent
    }

    private var reason: String {
        switch fallback {
        case .timedOut:
            "Your login shell (\(shellName)) took too long to start."
        case .couldNotStart:
            "Your login shell (\(shellName)) couldn’t be started."
        case let .exitedWithoutEnvironment(status):
            "Your login shell (\(shellName)) stopped with status \(status) before it finished starting."
        }
    }
}
