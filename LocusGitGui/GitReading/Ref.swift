import Foundation

/// A branch, remote branch or tag, from `git for-each-ref`.
nonisolated struct Ref: Equatable, Sendable {
    enum Kind: Sendable {
        case localBranch
        case remoteBranch
        case tag
    }

    /// The placeholders in the order `init(fields:)` reads them.
    private static let placeholders = [
        "%(refname)",
        "%(objectname)",
        // The commit an annotated tag points at. Empty for anything else.
        "%(*objectname)",
        "%(HEAD)",
        "%(symref)",
        "%(upstream)",
        "%(upstream:track,nobracket)",
    ]

    static let listCommand = GitCommand.reading([
        "for-each-ref",
        "--format=" + placeholders.joined(separator: "%00"),
        "refs/heads",
        "refs/remotes",
        "refs/tags",
    ])

    /// The full name, such as `refs/heads/main`.
    let name: String
    let commit: String
    let isCheckedOut: Bool
    /// Where a symbolic ref such as `refs/remotes/origin/HEAD` points.
    let symbolicTarget: String?
    let upstream: String?
    let ahead: Int?
    let behind: Int?
    /// The upstream is configured but the remote branch no longer exists.
    let isUpstreamGone: Bool

    var kind: Kind? {
        if name.hasPrefix("refs/heads/") {
            .localBranch
        } else if name.hasPrefix("refs/remotes/") {
            .remoteBranch
        } else if name.hasPrefix("refs/tags/") {
            .tag
        } else {
            nil
        }
    }

    static func readList(running run: (GitCommand) async throws -> ChildProcess.Result) async throws -> [Ref] {
        try await GitReadFailure.read("branches and tags", with: listCommand, running: run, parse: parseList)
    }

    /// One ref per line. A ref name can't contain a newline or NUL, so neither can any field.
    static func parseList(_ output: Data) throws -> [Ref] {
        try output.split(separator: UInt8(ascii: "\n")).map { line in
            let fields = try line.split(separator: 0, omittingEmptySubsequences: false).map(UnreadableGitOutput.text)
            guard fields.count == placeholders.count else {
                throw UnreadableGitOutput(reason: "Ref has \(fields.count) fields, expected \(placeholders.count)")
            }
            return Ref(fields: fields)
        }
    }

    init(
        name: String,
        commit: String,
        isCheckedOut: Bool = false,
        symbolicTarget: String? = nil,
        upstream: String? = nil,
        ahead: Int? = nil,
        behind: Int? = nil,
        isUpstreamGone: Bool = false
    ) {
        self.name = name
        self.commit = commit
        self.isCheckedOut = isCheckedOut
        self.symbolicTarget = symbolicTarget
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.isUpstreamGone = isUpstreamGone
    }

    private init(fields: [String]) {
        let upstream = fields[5].isEmpty ? nil : fields[5]
        let tracking = Self.tracking(fields[6], hasUpstream: upstream != nil)
        self.init(
            name: fields[0],
            commit: fields[2].isEmpty ? fields[1] : fields[2],
            isCheckedOut: fields[3] == "*",
            symbolicTarget: fields[4].isEmpty ? nil : fields[4],
            upstream: upstream,
            ahead: tracking.ahead,
            behind: tracking.behind,
            isUpstreamGone: tracking.isGone
        )
    }

    /// Git has no machine-readable form of these counts, only "ahead 2, behind 1" or "gone". The
    /// words are translated, which `GitEnvironment` keeps English. An upstream that is level with
    /// the branch prints nothing, so the counts are zero whenever there is an upstream.
    private static func tracking(_ text: String, hasUpstream: Bool) -> Tracking {
        guard hasUpstream else {
            return Tracking(ahead: nil, behind: nil, isGone: false)
        }
        if text == "gone" {
            return Tracking(ahead: nil, behind: nil, isGone: true)
        }
        var ahead = 0
        var behind = 0
        for part in text.split(separator: ", ") {
            let words = part.split(separator: " ")
            guard words.count == 2, let count = Int(words[1]) else { continue }
            if words[0] == "ahead" {
                ahead = count
            } else if words[0] == "behind" {
                behind = count
            }
        }
        return Tracking(ahead: ahead, behind: behind, isGone: false)
    }

    private struct Tracking {
        let ahead: Int?
        let behind: Int?
        let isGone: Bool
    }
}
