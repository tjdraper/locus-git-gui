import Foundation
import os

/// The commits of one history read so far, a page at a time as the list scrolls toward the end.
final class HistoryList {
    enum Change {
        /// A different history, or the same one read again from the start, once its first page
        /// has been read. For the same history, the commits shown until then are handed over, so
        /// the list can keep its place.
        case replaced(sameHistoryAs: [Commit]?)
        case appended(Range<Int>)
        /// Loading started or stopped, or a read failed, with the commits unchanged.
        case state
    }

    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "History")
    /// Small, so the window shows its history as soon as it can.
    private static let firstPageSize = 200
    private static let pageSize = 1000
    /// Reading the same history again keeps up to this many of the commits already shown, so a
    /// commit selected well down the list is still there after a new commit arrives.
    private static let longestReread = 5000
    /// Go to Parent reads on through the history until it finds the commit, but stops past this
    /// many rather than hold hundreds of megabytes of history for one very old merge.
    static let farthestFind = 50000
    /// How close to the end the list scrolls before the next page is read.
    private static let readAhead = 100

    private(set) var commits: [Commit] = []
    /// One per commit while the whole history is shown, and none during a search, whose commits
    /// aren't joined by their parents.
    private(set) var graph: [CommitGraphRow] = []
    /// The widest any row's graph reaches, in lanes, so every row's subject starts in the same place.
    private(set) var graphLanes = 0
    private(set) var scope: HistoryScope?
    private(set) var search: HistorySearch?
    private(set) var isComplete = false
    private(set) var isLoading = false
    private(set) var failure: GitFailure?
    var onChange: ((Change) -> Void)?

    /// Hands Git's output over as it arrives when given somewhere to hand it.
    private let run: (GitCommand, ((Data) -> Void)?) async throws -> ChildProcess.Result
    private var layout = CommitGraphLayout()
    /// How many commits `git log` has given, which leaves out a commit found by its hash.
    private var loggedCount = 0
    private var hashMatch: String?
    /// A commit found by its hash, shown first once the search's own matches start arriving.
    private var pendingHashMatch: Commit?
    /// Counted so output still arriving for a history that's been replaced is left out.
    private var generation = 0
    private var loading: Task<Void, Never>?
    /// The commits shown stay until the first page of what replaces them has been read, so a
    /// history read again after a commit doesn't empty and refill.
    private var isReplacing = false
    private var isReplacingSameHistory = false
    /// Counted so `find` can tell a read that added a page from one that ended without.
    private var pagesRead = 0

    init(run: @escaping (GitCommand, ((Data) -> Void)?) async throws -> ChildProcess.Result) {
        self.run = run
    }

    /// Nothing is read again when the history and search haven't changed, since a refresh asks
    /// after every change to the working tree. `isSameSelection` is true when only the commits it
    /// starts from have moved, such as after a commit, which reads as far as was shown before.
    func show(_ scope: HistoryScope, search: HistorySearch?, isSameSelection: Bool) {
        guard scope != self.scope || search != self.search else { return }
        let isSameHistory = isSameSelection && search == self.search && self.scope != nil
        self.scope = scope
        self.search = search
        let count = isSameHistory ? min(max(commits.count, Self.firstPageSize), Self.longestReread) : Self.firstPageSize
        start(reading: count, isSameHistory: isSameHistory)
    }

    /// After a failure, from the start.
    func reload() {
        guard scope != nil else { return }
        start(reading: max(commits.count, Self.firstPageSize), isSameHistory: true)
    }

    /// Called as rows come into view.
    func loadMore(near row: Int) {
        guard row >= commits.count - Self.readAhead else { return }
        loadNextPage()
    }

    func index(of hash: String) -> Int? {
        commits.firstIndex { $0.hash == hash }
    }

    enum FindResult {
        case found(Int)
        /// Further down than `farthestFind`.
        case tooFar
        case missing
    }

    /// Reads on until the commit is found or the history ends, for a parent well below its child.
    func find(_ hash: String) async -> FindResult {
        while !Task.isCancelled {
            if let index = index(of: hash), !isReplacing {
                return .found(index)
            }
            guard !isComplete, failure == nil else { return .missing }
            guard commits.count < Self.farthestFind else { return .tooFar }
            if loading == nil {
                loadNextPage()
            }
            guard let loading else { return .missing }
            let pages = pagesRead
            await loading.value
            // A read that ended without a page, such as when Git has gone missing, would otherwise
            // be tried again forever.
            guard pagesRead != pages else { return .missing }
        }
        return .missing
    }

    /// One commit by its hash, for a commit the history hasn't read, to show in its own window.
    func readCommit(_ hash: String) async -> Commit? {
        try? await HistoryReader.readHashMatch(hash) { try await self.run($0, nil) }
    }

    private func start(reading count: Int, isSameHistory: Bool) {
        loading?.cancel()
        loading = nil
        layout = CommitGraphLayout()
        loggedCount = 0
        hashMatch = nil
        pendingHashMatch = nil
        generation += 1
        isComplete = false
        failure = nil
        isReplacing = true
        isReplacingSameHistory = isSameHistory
        loadNextPage(count: count)
    }

    private func loadNextPage(count: Int = pageSize) {
        guard let scope, loading == nil, !isComplete, failure == nil else { return }
        let search = search
        let isFirstPage = loggedCount == 0 && (isReplacing || commits.isEmpty)
        let skip = loggedCount
        let generation = generation
        isLoading = true
        onChange?(.state)
        loading = Task { [weak self, run] in
            let started = ContinuousClock.now
            do {
                if isFirstPage, let candidate = search?.hashCandidate {
                    self?.pendingHashMatch = try await HistoryReader.readHashMatch(candidate) { try await run($0, nil) }
                }
                let read: Int
                if let search {
                    // A search can take seconds between matches, so each is shown as it's found.
                    read = try await HistoryReader.stream(scope, search: search, commits: skip ..< skip + count) { command, onOutput in
                        try await run(command, onOutput)
                    } receive: { [weak self] commits in
                        guard self?.generation == generation else { return }
                        self?.receive(commits)
                    }
                } else {
                    // A page arrives whole, so a history read again finds its selected commit in it.
                    let page = try await HistoryReader.read(scope, search: nil, skip: skip, count: count) { try await run($0, nil) }
                    try Task.checkCancellation()
                    self?.receive(page)
                    read = page.count
                }
                try Task.checkCancellation()
                self?.finishPage(isLast: read < count)
                Self.log.info("Read \(read) commits in \(ContinuousClock.now - started, privacy: .public)")
            } catch is CancellationError {
                return
            } catch is RepositoryCommandRunner.NoUsableGit {
                self?.finishLoading()
            } catch {
                self?.fail(error)
            }
        }
    }

    private func receive(_ page: [Commit]) {
        let previous = takeReplacedCommits()
        let start = commits.count
        if let match = pendingHashMatch {
            pendingHashMatch = nil
            hashMatch = match.hash
            commits.append(match)
        }
        loggedCount += page.count
        commits += page.filter { $0.hash != hashMatch }
        if search == nil {
            // Only the row as drawn is kept, which also keeps a very wide history's rows small.
            let rows = commits[start...].map { layout.add($0.hash, parents: $0.parents).limited(toLanes: CommitGraphRow.widestDrawn) }
            graph += rows
            graphLanes = rows.reduce(graphLanes) { max($0, $1.width) }
        }
        onChange?(previous.map { .replaced(sameHistoryAs: isReplacingSameHistory ? $0 : nil) } ?? .appended(start ..< commits.count))
    }

    /// A page with no commits of its own still replaces the history it was read for, and still
    /// shows a commit found by its hash.
    private func finishPage(isLast: Bool) {
        if isReplacing || pendingHashMatch != nil {
            receive([])
        }
        pagesRead += 1
        isComplete = isLast
        finishLoading()
    }

    /// The commits shown before, when this is the first page of what replaces them.
    private func takeReplacedCommits() -> [Commit]? {
        guard isReplacing else { return nil }
        isReplacing = false
        let previous = commits
        commits = []
        graph = []
        graphLanes = 0
        return previous
    }

    private func finishLoading() {
        loading = nil
        isLoading = false
        onChange?(.state)
    }

    /// A history that couldn't be read shows nothing rather than the one it was replacing.
    private func fail(_ error: any Error) {
        switch error {
        case let failure as GitReadFailure:
            self.failure = GitFailure(
                summary: failure.outputWasUnreadable
                    ? "Locus Git Gui couldn’t read Git’s report on this history."
                    : "Git couldn’t read this history.",
                arguments: failure.command.arguments,
                result: failure.result
            )
        case let ChildProcess.Failure.couldNotStart(error):
            failure = GitFailure(
                summary: "Git couldn’t start in this repository’s folder.",
                arguments: [],
                result: ChildProcess.Result(status: -1, standardOutput: Data(), standardError: Data(error.localizedDescription.utf8))
            )
        default:
            Self.log.error("Reading history failed: \(String(describing: type(of: error)), privacy: .public)")
        }
        if let previous = takeReplacedCommits() {
            onChange?(.replaced(sameHistoryAs: isReplacingSameHistory ? previous : nil))
        }
        finishLoading()
    }
}
