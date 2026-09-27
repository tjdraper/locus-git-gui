import Foundation

/// Addresses Git can fetch from, as someone copies them from a hosting site or a colleague: a URL
/// such as `https://github.com/owner/repository.git`, or SSH's shorter `git@github.com:owner/repository.git`.
nonisolated enum RemoteURL {
    /// Whether text on the clipboard is worth offering as an address, which a word or a sentence isn't.
    static func looksLikeRemote(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return false }
        if text.firstMatch(of: #/^(?:https?|ssh|git|file)://[^/\s]*\/?./#) != nil {
            return true
        }
        return text.firstMatch(of: #/^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[^/\s].*$/#) != nil
    }

    /// The folder Git would name a clone of it: the last part of the path, without `.git`.
    static func repositoryName(from address: String) -> String? {
        var path = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if path.hasSuffix("/.git") {
            path.removeLast("/.git".count)
        } else if path.hasSuffix(".git") {
            path.removeLast(".git".count)
        }
        let name = path.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        return name.isEmpty ? nil : name
    }
}
