import Foundation
import os

/// The commits of one history read so far, a page at a time as the list scrolls toward the end.
final class HistoryList {
    enum Change {
        /// A different history, or the same one read again from the start, once its first page
        /// has been read. The commits shown until then are handed over, so the list can keep its
        /// place.
        case replaced(previous: [Commit])
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
    /// How close to the end the list scrolls before the next page is read.
    private static let readAhead = 100

    private(set) var commits: [Commit] = []
    /// One per commit while the whole history is shown, and none during a search, whose commits
    /// aren't joined by their parents.
    private(set) var graph: [CommitGraphRow] = []
    private(set) var scope: HistoryScope?
    private(set) var search: HistorySearch?
    private(set) var isComplete = false
    private(set) var isLoading = false
    private(set) var failure: GitFailure?
    var onChange: ((Change) -> Void)?

    private let run: (GitCommand) async throws -> ChildProcess.Result
    private var layout = CommitGraphLayout()
    /// How many commits `git log` has given, which leaves out a commit found by its hash.
    private var loggedCount = 0
    private var hashMatch: String?
    private var loading: Task<Void, Never>?
    /// The commits shown stay until the first page of what replaces them has been read, so a
    /// history read again after a commit doesn't empty and refill.
    private var isReplacing = false
    /// Counted so `find` can tell a read that added a page from one that ended without.
    private var pagesRead = 0

    init(run: @escaping (GitCommand) async throws -> ChildProcess.Result) {
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
        start(reading: count)
    }

    /// After a failure, from the start.
    func reload() {
        guard scope != nil else { return }
        start(reading: max(commits.count, Self.firstPageSize))
    }

    /// Called as rows come into view.
    func loadMore(near row: Int) {
        guard row >= commits.count - Self.readAhead else { return }
        loadNextPage()
    }

    func index(of hash: String) -> Int? {
        commits.firstIndex { $0.hash == hash }
    }

    /// Reads on until the commit is found or the history ends, for a parent well below its child.
    func find(_ hash: String) async -> Int? {
        while !Task.isCancelled {
            if let index = index(of: hash), !isReplacing {
                return index
            }
            guard !isComplete, failure == nil else { return nil }
            if loading == nil {
                loadNextPage()
            }
            guard let loading else { return nil }
            let pages = pagesRead
            await loading.value
            // A read that ended without a page, such as when Git has gone missing, would otherwise
            // be tried again forever.
            guard pagesRead != pages else { return nil }
        }
        return nil
    }

    private func start(reading count: Int) {
        loading?.cancel()
        loading = nil
        layout = CommitGraphLayout()
        loggedCount = 0
        hashMatch = nil
        isComplete = false
        failure = nil
        isReplacing = true
        loadNextPage(count: count)
    }

    private func loadNextPage(count: Int = pageSize) {
        guard let scope, loading == nil, !isComplete, failure == nil else { return }
        let search = search
        let isFirstPage = loggedCount == 0 && (isReplacing || commits.isEmpty)
        let skip = loggedCount
        isLoading = true
        onChange?(.state)
        loading = Task { [weak self, run] in
            let started = ContinuousClock.now
            do {
                var match: Commit?
                if isFirstPage, let candidate = search?.hashCandidate {
                    match = try await HistoryReader.readHashMatch(candidate, running: run)
                }
                let page = try await HistoryReader.read(scope, search: search, skip: skip, count: count, running: run)
                try Task.checkCancellation()
                self?.append(page, hashMatch: match, isLast: page.count < count)
                Self.log.info("Read \(page.count) commits in \(ContinuousClock.now - started, privacy: .public)")
            } catch is CancellationError {
                return
            } catch is RepositoryCommandRunner.NoUsableGit {
                self?.finishLoading()
            } catch {
                self?.fail(error)
            }
        }
    }

    private func append(_ page: [Commit], hashMatch match: Commit?, isLast: Bool) {
        let previous = takeReplacedCommits()
        pagesRead += 1
        let start = commits.count
        if let match {
            hashMatch = match.hash
            commits.append(match)
        }
        loggedCount += page.count
        commits += page.filter { $0.hash != hashMatch }
        if search == nil {
            graph += commits[start...].map { layout.add($0.hash, parents: $0.parents) }
        }
        isComplete = isLast
        loading = nil
        isLoading = false
        onChange?(previous.map { .replaced(previous: $0) } ?? .appended(start ..< commits.count))
    }

    /// The commits shown before, when this is the first page of what replaces them.
    private func takeReplacedCommits() -> [Commit]? {
        guard isReplacing else { return nil }
        isReplacing = false
        let previous = commits
        commits = []
        graph = []
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
            onChange?(.replaced(previous: previous))
        }
        finishLoading()
    }
}
