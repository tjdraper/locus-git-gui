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

    /// The same list with the tracking field left empty. Counting how far each branch is from its
    /// upstream is most of the work when thousands of branches have one.
    static let listCommandWithoutTracking = GitCommand.reading([
        "for-each-ref",
        "--format=" + (placeholders.dropLast() + [""]).joined(separator: "%00"),
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
        try await GitReadFailure.readConcurrently("branches and tags", with: listCommand, running: run, parse: parseList)
    }

    /// Takes each branch's counts from `previous` when neither it nor its upstream has moved, which
    /// is every refresh that follows a change to the files alone. Otherwise Git counts them again.
    static func readList(
        reusingCountsFrom previous: [Ref],
        running run: (GitCommand) async throws -> ChildProcess.Result
    ) async throws -> [Ref] {
        let refs = try await GitReadFailure.readConcurrently(
            "branches and tags",
            with: listCommandWithoutTracking,
            running: run
        ) { output in
            try reusingCounts(in: parseList(output), from: previous)
        }
        guard let refs else {
            return try await readList(running: run)
        }
        return refs
    }

    /// Nil when a branch or its upstream has moved since `previous`, whose counts no longer hold.
    private static func reusingCounts(in refs: [Ref], from previous: [Ref]) -> [Ref]? {
        let commits = Dictionary(refs.map { ($0.name, $0.commit) }) { first, _ in first }
        let previousCommits = Dictionary(previous.map { ($0.name, $0.commit) }) { first, _ in first }
        let previousRefs = Dictionary(previous.map { ($0.name, $0) }) { first, _ in first }
        var reused: [Ref] = []
        reused.reserveCapacity(refs.count)
        for ref in refs {
            guard let upstream = ref.upstream else {
                reused.append(ref)
                continue
            }
            guard let old = previousRefs[ref.name], old.commit == ref.commit, old.upstream == upstream,
                  commits[upstream] == previousCommits[upstream]
            else {
                return nil
            }
            reused.append(Ref(
                name: ref.name,
                commit: ref.commit,
                isCheckedOut: ref.isCheckedOut,
                symbolicTarget: ref.symbolicTarget,
                upstream: upstream,
                ahead: old.ahead,
                behind: old.behind,
                isUpstreamGone: old.isUpstreamGone
            ))
        }
        return reused
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
