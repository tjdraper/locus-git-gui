import SwiftUI

/// The plain explanation above Git's output: why a recognized failure happened and what to do, or
/// for any other, that Git's output says why.
struct GitFailureExplanation: View {
    let failure: GitFailure
    let repository: Repository

    var body: some View {
        switch failure.recognized {
        case let .lockExists(lock):
            Text("""
            Git keeps \(displayPath(lock)) while it changes the repository, so two commands can’t \
            change it at once. Another Git process is working here, or one stopped without \
            cleaning up.
            """)
        case .accessDenied:
            Text("""
            macOS is keeping Locus Git Gui out of this folder. Allow access under Files & Folders \
            in Privacy & Security settings, then try again.
            """)
        case .pushBehindRemote:
            Text("""
            The remote has commits this branch doesn’t, and pushing would drop them. Pull to bring \
            them in, then push again. Force Push replaces the remote’s branch with this one, and \
            its commits are no longer on the remote.
            """)
        case .pushLeaseStale:
            Text("""
            The remote’s branch has changed since this repository last fetched it, so the force \
            push stopped rather than drop commits nobody here has seen. Fetch, look at what \
            arrived, then decide.
            """)
        case let .pushRefusedByRemote(reason, messages):
            remoteRefusal(reason: reason, messages: messages)
        case .pullNeedsStrategy:
            Text("This branch and its upstream have both moved on, and Git needs to know whether to merge or rebase them.")
        case let .upstreamGone(branch):
            Text("""
            The remote no longer has “\(branch)”, the branch this one pulls from. It was deleted \
            there, often after being merged. Push recreates it from this branch.
            """)
        case let .authenticationFailed(method, server):
            Text(authenticationDescription(method, server: server))
        case let .hostKeyChanged(host):
            Text("""
            The server at \(host ?? "this address") identified itself with a different key from \
            the one SSH remembers, so SSH refused to connect. That happens when a server is \
            replaced, and also when someone is intercepting the connection. Check with the \
            server’s owner. Once the new key is confirmed, remove the old one in Terminal with \
            “\(Self.forgetHostCommand(host))”.
            """)
        case let .unreachable(host):
            Text("""
            Git couldn’t reach \(host ?? "the server"), which is a problem with the network or the \
            address rather than with a repository. Check the connection and the remote’s address.
            """)
        case nil:
            Text("Git couldn’t finish. Its output below says why.")
                .foregroundStyle(.secondary)
        }
    }

    /// The server's own words come first, since they say what it wants, such as a protected branch
    /// needing a pull request.
    @ViewBuilder
    private func remoteRefusal(reason: String, messages: [String]) -> some View {
        Text("The server turned the push down (\(reason)).\(messages.isEmpty ? "" : " It said:")")
        if !messages.isEmpty {
            Text(messages.joined(separator: "\n"))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 2)
                }
        }
    }

    private func authenticationDescription(_ method: RecognizedGitFailure.AuthenticationMethod, server: String?) -> String {
        let server = server ?? "The server"
        switch method {
        case .sshKey:
            return """
            \(server) didn’t accept an SSH key from this Mac. Check that your key is added to your \
            account there, and to the SSH agent if it has a passphrase.
            """
        case .https:
            return """
            \(server) didn’t accept the username and password or token. A token may have expired \
            or lack access to this repository. Try again to enter them again.
            """
        }
    }

    /// A host on another port is written in brackets, which the shell would otherwise try to match
    /// against file names.
    private static func forgetHostCommand(_ host: String?) -> String {
        guard let host else { return "ssh-keygen -R <host>" }
        return host.contains("[") ? "ssh-keygen -R '\(host)'" : "ssh-keygen -R \(host)"
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

/// A changed host key can mean the connection is being intercepted, so it's marked as more serious
/// than a failure that only stops the command.
struct GitFailureSymbol: View {
    let failure: GitFailure

    var body: some View {
        if case .hostKeyChanged = failure.recognized {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.yellow)
        }
    }
}
