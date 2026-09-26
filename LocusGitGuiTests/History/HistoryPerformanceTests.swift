import Foundation
import Testing

/// Times the history's reading and graph layout against a large repository, the way the app reads
/// it. Skipped unless `LOCUS_PERFORMANCE_REPOSITORY` names one, since the repositories worth
/// measuring are far too big to build in a test. See Scripts/README.md.
@Suite(.enabled(if: PerformanceRepository.url != nil), .serialized)
struct HistoryPerformanceTests {
    private let runner = GitRunner(executableURL: TestGit.executableURL, environment: ProcessInfo.processInfo.environment)

    private func run(_ command: GitCommand) async throws -> ChildProcess.Result {
        try await runner.run(command, in: #require(PerformanceRepository.url))
    }

    private func head() async throws -> HistoryScope {
        let result = try await run(.reading(["rev-parse", "HEAD"]))
        let hash = String(bytes: result.standardOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return HistoryScope(tips: [hash])
    }

    /// Appended to a file beside the repository, since a test's printed output doesn't reach
    /// `xcodebuild`.
    private func report(_ what: String, _ duration: Duration) {
        write("\(what): \(duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))")
    }

    private func write(_ result: String) {
        guard let repository = PerformanceRepository.url else { return }
        let file = repository.deletingLastPathComponent().appending(path: repository.lastPathComponent + "-performance.txt")
        let line = "\(Date().formatted(.iso8601)) \(result)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    /// Read and laid out as the app does it, returning how long that took.
    private func readPage(_ scope: HistoryScope, search: HistorySearch? = nil, skip: Int, count: Int) async throws -> (Duration, Int) {
        let clock = ContinuousClock()
        var commits: [Commit] = []
        let duration = try await clock.measure {
            commits = try await HistoryReader.read(scope, search: search, skip: skip, count: count, running: run)
            var layout = CommitGraphLayout()
            for commit in commits {
                _ = layout.add(commit.hash, parents: commit.parents)
            }
        }
        return (duration, commits.count)
    }

    @Test
    func firstPage() async throws {
        let scope = try await head()
        let (duration, count) = try await readPage(scope, skip: 0, count: 200)
        report("first page of \(count)", duration)
    }

    @Test
    func pagesDeepInTheHistory() async throws {
        let scope = try await head()
        for skip in [10000, 100_000, 500_000] {
            let (duration, count) = try await readPage(scope, skip: skip, count: 1000)
            report("page of \(count) after skipping \(skip)", duration)
        }
    }

    @Test
    func scrollingThroughTwentyPages() async throws {
        let scope = try await head()
        let clock = ContinuousClock()
        var read = 0
        let duration = try await clock.measure {
            read += try await readPage(scope, skip: 0, count: 200).1
            for _ in 0 ..< 20 {
                read += try await readPage(scope, skip: read, count: 1000).1
            }
        }
        report("\(read) commits a page at a time", duration)
    }

    /// What the history holds after scrolling a long way: every commit read, and its graph row.
    @Test
    func memoryAfterScrollingFar() async throws {
        let scope = try await head()
        let before = Self.footprint()
        var commits: [Commit] = []
        var rows: [CommitGraphRow] = []
        var layout = CommitGraphLayout()
        while commits.count < 100_000 {
            let page = try await HistoryReader.read(scope, search: nil, skip: commits.count, count: 1000, running: run)
            guard !page.isEmpty else { break }
            commits += page
            rows += page.map { layout.add($0.hash, parents: $0.parents).limited(toLanes: CommitGraphRow.widestDrawn) }
        }
        let bytes = Self.footprint() - before
        let each = bytes / max(commits.count, 1)
        write("memory for \(commits.count) commits and \(rows.count) graph rows: \(bytes / 1_048_576) MB, \(each) bytes each")
        let lines = rows.reduce(0) { $0 + $1.lines.count }
        write("graph: at most \(rows.map(\.width).max() ?? 0) lanes wide, \(lines / max(rows.count, 1)) lines a row on average")
    }

    /// The process's memory as Activity Monitor reports it.
    private static func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    /// A search with few matches reads the whole history, so what counts is how soon the first
    /// one shows.
    @Test
    func firstMatchOfARareSearch() async throws {
        let scope = try await head()
        let runner = runner
        let repository = try #require(PerformanceRepository.url)
        let clock = ContinuousClock()
        let started = clock.now
        var first: Duration?
        let count = try await HistoryReader.stream(
            scope,
            search: HistorySearch(text: "lane 3", field: .message),
            commits: 0 ..< 200
        ) { command, onOutput in
            try await Self.collect(runner.stream(command, in: repository), onOutput: onOutput)
        } receive: { _ in
            first = first ?? clock.now - started
        }
        report("first of \(count) matches for a rare message, streamed", first ?? clock.now - started)
        report("all of them", clock.now - started)
    }

    private static func collect(
        _ events: AsyncThrowingStream<ChildProcess.Event, any Error>,
        onOutput: (Data) -> Void
    ) async throws -> ChildProcess.Result {
        var output = Data()
        for try await event in events {
            switch event {
            case let .standardOutput(data):
                output.append(data)
                onOutput(data)
            case .standardError:
                break
            case let .exited(status):
                return ChildProcess.Result(status: status, standardOutput: output, standardError: Data())
            }
        }
        throw CancellationError()
    }

    @Test
    func searches() async throws {
        let scope = try await head()
        for search in [HistorySearch(text: "lane 3", field: .message), HistorySearch(text: "Grace", field: .author)] {
            let (duration, count) = try await readPage(scope, search: search, skip: 0, count: 200)
            report("first \(count) matches for \(search?.field.rawValue ?? "")", duration)
        }
        // A partial clone, such as a blobless clone of the kernel, would download the contents of
        // every file in the history to search their changes. Git marks one with a promisor remote,
        // or with `extensions.partialClone` before 2.26.
        let promisor = try await run(.reading(["config", "--get-regexp", #"^remote\..*\.promisor$"#, "true"]))
        let partialClone = try await run(.reading(["config", "extensions.partialClone"]))
        guard promisor.status != 0, partialClone.status != 0 else {
            write("search in changes skipped: this is a partial clone")
            return
        }
        let changes = HistorySearch(text: "Change 12345\n", field: .changes)
        let (duration, count) = try await readPage(scope, search: changes, skip: 0, count: 200)
        report("first \(count) matches for changes", duration)
    }
}

/// Named outside the suite, which can't refer to itself in its own traits.
nonisolated enum PerformanceRepository {
    static let url = ProcessInfo.processInfo.environment["LOCUS_PERFORMANCE_REPOSITORY"]
        .map { URL(filePath: $0, directoryHint: .isDirectory) }
}
