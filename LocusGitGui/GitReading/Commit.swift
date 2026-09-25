import Foundation

/// One commit from `git log`.
nonisolated struct Commit: Equatable, Sendable {
    struct Signature: Equatable, Sendable {
        let name: String
        let email: String
        let date: Date
    }

    /// The placeholders in the order `init(fields:)` reads them.
    private static let placeholders = ["%H", "%P", "%an", "%ae", "%at", "%cn", "%ce", "%ct", "%s"]

    let hash: String
    /// Empty for a root commit, two or more for a merge.
    let parents: [String]
    let author: Signature
    let committer: Signature
    let subject: String

    /// `log.showSignature` in the user's config would otherwise put GPG's output between commits.
    static func logCommand(_ arguments: [String]) -> GitCommand {
        .reading(["log", "-z", "--no-show-signature", "--format=" + placeholders.joined(separator: "%x00")] + arguments)
    }

    /// With `-z`, every field and every commit ends in a NUL, so commits are told apart by counting
    /// fields. A subject or a root commit's parents can be empty, so empty fields are kept.
    static func parseLog(_ output: Data) throws -> [Commit] {
        var fields = try output.split(separator: 0, omittingEmptySubsequences: false).map(UnreadableGitOutput.text)
        if fields.last?.isEmpty == true {
            fields.removeLast()
        }
        guard fields.count.isMultiple(of: placeholders.count) else {
            throw UnreadableGitOutput(reason: "Log has \(fields.count) fields, not a multiple of \(placeholders.count)")
        }
        return try stride(from: 0, to: fields.count, by: placeholders.count).map { start in
            try Commit(fields: fields[start ..< start + placeholders.count])
        }
    }

    init(hash: String, parents: [String], author: Signature, committer: Signature, subject: String) {
        self.hash = hash
        self.parents = parents
        self.author = author
        self.committer = committer
        self.subject = subject
    }

    private init(fields: ArraySlice<String>) throws {
        let fields = Array(fields)
        self.init(
            hash: fields[0],
            parents: fields[1].split(separator: " ").map(String.init),
            author: try Self.signature(name: fields[2], email: fields[3], timestamp: fields[4]),
            committer: try Self.signature(name: fields[5], email: fields[6], timestamp: fields[7]),
            subject: fields[8]
        )
    }

    private static func signature(name: String, email: String, timestamp: String) throws -> Signature {
        guard let seconds = TimeInterval(timestamp) else {
            throw UnreadableGitOutput(reason: "Malformed commit date")
        }
        return Signature(name: name, email: email, date: Date(timeIntervalSince1970: seconds))
    }
}
