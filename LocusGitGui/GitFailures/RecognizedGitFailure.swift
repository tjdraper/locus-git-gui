import Foundation

/// A failure the app knows the likely cause of and a next step for. Git's messages are matched in
/// English, which `GitEnvironment` makes sure they are.
nonisolated enum RecognizedGitFailure: Equatable, Sendable {
    enum AuthenticationMethod: Equatable, Sendable {
        case sshKey
        /// A username with a password or token.
        case https
    }

    /// Another Git process holds a lock, or one crashed and left it behind. Covers `index.lock`
    /// and the locks on refs such as `refs/heads/main.lock`.
    case lockExists(URL)
    /// macOS privacy protection kept Git out of the folder. This is the system's wording for EPERM.
    case accessDenied
    /// The remote has commits the branch doesn't, so pushing would drop them.
    case pushBehindRemote
    /// `--force-with-lease` found the remote's branch had moved since it was last fetched.
    case pushLeaseStale
    /// The server turned the push down, such as for a protected branch or in a hook of its own.
    /// `messages` is what the server said, from Git's `remote:` lines, and `reason` Git's summary.
    case pushRefusedByRemote(reason: String, messages: [String])
    /// A pull on a branch that has diverged from its upstream, with nothing configured to say
    /// whether to merge or rebase.
    case pullNeedsStrategy
    /// A pull whose upstream has been deleted from the remote. `branch` is its name there.
    case upstreamGone(branch: String)
    /// `server` is the host, or the account and host SSH names, such as `git@github.com`.
    case authenticationFailed(AuthenticationMethod, server: String?)
    /// The server's host key isn't the one SSH remembers, which SSH refuses to go past.
    case hostKeyChanged(host: String?)
    /// The server couldn't be found or reached, which is the network rather than the repository.
    case unreachable(host: String?)

    static func recognize(_ result: ChildProcess.Result) -> RecognizedGitFailure? {
        guard result.status != 0 else {
            return nil
        }
        let standardError = String(bytes: result.standardError, encoding: .utf8) ?? ""
        let standardOutput = String(bytes: result.standardOutput, encoding: .utf8) ?? ""
        let output = TerminalOutput.rendered(standardError + "\n" + standardOutput)
        if let match = output.firstMatch(of: #/Unable to create '(?<path>[^']+\.lock)': File exists\./#) {
            return .lockExists(URL(filePath: String(match.output.path)))
        }
        if output.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") {
            return .hostKeyChanged(host: output.firstMatch(of: #/Host key for (?<host>\S+) has changed/#).map { String($0.host) })
        }
        if let push = recognizePush(output) {
            return push
        }
        if output.contains("Need to specify how to reconcile divergent branches") {
            return .pullNeedsStrategy
        }
        // Git breaks this sentence over two lines.
        let gone = #/merge with the ref 'refs/heads/(?<branch>[^']+)'\s+from the remote, but no such ref was fetched/#
        if let match = output.firstMatch(of: gone) {
            return .upstreamGone(branch: String(match.branch))
        }
        if let authentication = recognizeAuthentication(output) {
            return authentication
        }
        if let unreachable = recognizeUnreachable(output) {
            return unreachable
        }
        if output.contains("Operation not permitted") {
            return .accessDenied
        }
        return nil
    }

    /// Git lists each ref it tried, such as ` ! [rejected]        main -> main (fetch first)`.
    private static func recognizePush(_ output: String) -> RecognizedGitFailure? {
        if let match = output.firstMatch(of: #/! \[remote rejected\] .+ \((?<reason>[^)]+)\)/#) {
            let messages = output.split(separator: "\n")
                .filter { $0.hasPrefix("remote: ") && GitProgress(line: String($0)) == nil }
                .map { $0.dropFirst("remote: ".count).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return .pushRefusedByRemote(reason: String(match.reason), messages: messages)
        }
        guard let match = output.firstMatch(of: #/! \[rejected\] .+ \((?<reason>[^)]+)\)/#) else {
            return nil
        }
        switch match.reason {
        case "stale info": return .pushLeaseStale
        case "fetch first", "non-fast-forward": return .pushBehindRemote
        default: return nil
        }
    }

    /// Git says so for HTTPS, and when it couldn't ask for a username or password at all. SSH says
    /// which methods the server would have taken.
    private static func recognizeAuthentication(_ output: String) -> RecognizedGitFailure? {
        if let match = output.firstMatch(of: #/Authentication failed for '(?<url>[^']+)'/#) {
            return .authenticationFailed(.https, server: URLComponents(string: String(match.url))?.host)
        }
        if let match = output.firstMatch(of: #/could not read (?:Username|Password) for '(?<url>[^']+)'/#) {
            return .authenticationFailed(.https, server: URLComponents(string: String(match.url))?.host)
        }
        if let match = output.firstMatch(of: #/(?m)^(?<server>\S+): Permission denied \((?<methods>[^)]+)\)/#) {
            return .authenticationFailed(.sshKey, server: String(match.server))
        }
        return nil
    }

    private static func recognizeUnreachable(_ output: String) -> RecognizedGitFailure? {
        let patterns = [
            #/Could not resolve hostname (?<host>[^\s:]+)/#,
            #/Could not resolve host: (?<host>[^\s']+)/#,
            #/Failed to connect to (?<host>\S+) port/#,
            #/connect to host (?<host>\S+) port \d+: (?:Connection refused|Operation timed out|Network is unreachable|No route to host)/#,
        ]
        for pattern in patterns {
            if let match = output.firstMatch(of: pattern) {
                return .unreachable(host: String(match.host))
            }
        }
        return nil
    }
}
