import Foundation

/// What Git or SSH is asking for, read from the question it passes the askpass helper. The wording
/// is theirs, in English, which `GitEnvironment` makes sure of. A question the app doesn't know is
/// still asked, in Git's or SSH's own words.
nonisolated enum CredentialPrompt: Equatable, Sendable {
    /// Git asking for an HTTPS username, such as `github.com`.
    case username(server: String)
    /// Git asking for an HTTPS password or token, or SSH for an account's password.
    case password(account: String?, server: String)
    /// SSH asking to unlock a key. The path can be cut short by SSH.
    case passphrase(keyPath: String)
    /// SSH meeting a server for the first time, asking whether to trust its key.
    case unknownHost(host: String, keyType: String?, fingerprint: String?)
    /// A yes or no question from SSH, such as the agent confirming a key's use.
    case confirmation(String)
    /// A notice from SSH that ends by itself, such as waiting for a security key to be touched.
    case notice(String)
    case other(String)

    static func parse(_ text: String, hint: String?) -> CredentialPrompt {
        if hint == "none" {
            return .notice(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let match = text.firstMatch(of: #/^Username for '(?<url>[^']+)': ?$/#) {
            return .username(server: server(in: String(match.url)))
        }
        if let match = text.firstMatch(of: #/^Password for '(?<url>[^']+)': ?$/#) {
            let url = String(match.url)
            return .password(account: account(in: url), server: server(in: url))
        }
        if let match = text.firstMatch(of: #/^Enter passphrase for key '(?<path>.+)': ?$/#) {
            return .passphrase(keyPath: String(match.path))
        }
        if text.contains("The authenticity of host"), text.contains("continue connecting") {
            return unknownHost(text)
        }
        if let match = text.firstMatch(of: #/^\(?(?<user>[^@\s()]+)@(?<host>[^\s()']+)\)?'?s? ?[Pp]assword: ?$/#) {
            return .password(account: String(match.user), server: String(match.host))
        }
        if hint == "confirm" {
            return .confirmation(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return .other(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The answer that trusts a new host, or says yes to SSH's question.
    static let yes = "yes"

    /// SSH writes at most 100 bytes of a key's path into its question (`%.100s`), so a longer path
    /// arrives cut short and its last part isn't the key's name.
    static func isCutShort(_ keyPath: String) -> Bool {
        keyPath.utf8.count >= 100
    }

    /// `[127.0.0.1]:2222 ([127.0.0.1]:2222)` names a host on another port; the part before the
    /// parenthesis is enough. Older SSH writes "fingerprint is SHA256:…", newer "fingerprint is: …".
    private static func unknownHost(_ text: String) -> CredentialPrompt {
        let host = text.firstMatch(of: #/authenticity of host '(?<host>[^' ]+)/#).map { String($0.host) } ?? "the server"
        // A base64 or hex fingerprint has no full stop, so one at the end ends the sentence.
        let fingerprint = text.firstMatch(of: #/(?<fingerprint>(?:SHA256|MD5):\S+)/#)
            .map { String($0.fingerprint.hasSuffix(".") ? $0.fingerprint.dropLast() : $0.fingerprint) }
        let keyType = text.firstMatch(of: #/(?<type>[A-Z0-9-]+) key fingerprint/#).map { String($0.type) }
        return .unknownHost(host: host, keyType: keyType, fingerprint: fingerprint)
    }

    /// `https://github.com` or `https://git@github.com/owner/repo.git` to `github.com`.
    private static func server(in url: String) -> String {
        guard let components = URLComponents(string: url), let host = components.host else {
            return url
        }
        return components.port.map { "\(host):\($0)" } ?? host
    }

    private static func account(in url: String) -> String? {
        guard let user = URLComponents(string: url)?.user, !user.isEmpty else {
            return nil
        }
        return user.removingPercentEncoding ?? user
    }
}
