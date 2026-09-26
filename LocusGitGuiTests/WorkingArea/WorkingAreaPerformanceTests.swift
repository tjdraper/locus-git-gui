import Foundation
import Testing

/// Times the working area against a repository made with
/// `Scripts/GenerateTestRepository.swift --working-changes <n>`, which leaves thousands of changed and
/// untracked files. Skipped unless `LOCUS_PERFORMANCE_REPOSITORY` names one. Stages and unstages
/// everything, and leaves the repository as it found it. See Scripts/README.md.
@Suite(.enabled(if: PerformanceRepository.url != nil), .serialized)
struct WorkingAreaPerformanceTests {
    private let runner = GitRunner(executableURL: TestGit.executableURL, environment: ProcessInfo.processInfo.environment)
    private let metrics = DiffLayout.Metrics(advance: 6.6, lineHeight: 17)

    private func run(_ command: GitCommand) async throws -> ChildProcess.Result {
        try await runner.run(command, in: #require(PerformanceRepository.url))
    }

    /// As the app reads a patch: parsed as it arrives, without keeping Git's output.
    private func readPatch(
        _ command: GitCommand,
        _ limits: PatchParser.Limits
    ) async throws -> (result: ChildProcess.Result, files: [FilePatch]) {
        var parser = PatchParser(limits: limits)
        for try await event in try runner.stream(command, in: #require(PerformanceRepository.url)) {
            switch event {
            case let .standardOutput(data):
                parser.consume(data)
            case .standardError:
                break
            case let .exited(status):
                return (ChildProcess.Result(status: status, standardOutput: Data(), standardError: Data()), parser.finish())
            }
        }
        throw CancellationError()
    }

    private func report(_ what: String, _ duration: Duration) {
        guard let repository = PerformanceRepository.url else { return }
        let file = repository.deletingLastPathComponent().appending(path: repository.lastPathComponent + "-performance.txt")
        let formatted = duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))
        let line = "\(Date().formatted(.iso8601)) working area: \(what): \(formatted)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    private func readStatus() async throws -> (RepositoryStatus, Duration) {
        var status: RepositoryStatus?
        let duration = try await ContinuousClock().measure {
            status = try RepositoryStatus(parsing: try await run(RepositoryStatus.command).standardOutput)
        }
        return (try #require(status), duration)
    }

    private func readWorkingArea(_ status: RepositoryStatus, _ what: String) async throws {
        let workTree = try #require(PerformanceRepository.url)
        var files: [DiffFile] = []
        let read = try await ContinuousClock().measure {
            files = try await WorkingAreaDiff.read(status, options: DiffOptions(), workTree: workTree, readingPatch: readPatch)
        }
        let kept = files.reduce(0) { $0 + $1.patch.hunks.reduce(0) { $0 + $1.lines.count } }
        let leftOut = files.count { $0.patch.content != .shown }
        report("\(what): read \(files.count) files, \(kept) lines kept, \(leftOut) files left out", read)
        var rows = 0
        let laidOut = ContinuousClock().measure {
            let numberColumns = DiffLayout.numberColumns(of: files)
            let document = DiffDocument(files: files, collapsed: [], style: .inline)
            _ = DiffLayout(document: document, files: files, metrics: metrics, width: 700, numberColumns: numberColumns)
            rows = document.blocks.count
        }
        report("\(what): \(rows) rows laid out", laidOut)
    }

    @Test
    func thousandsOfChangedAndUntrackedFiles() async throws {
        let (status, statusDuration) = try await readStatus()
        let summary = WorkingAreaSummary(status)
        report("status of \(summary.description)", statusDuration)
        try await readWorkingArea(status, "unstaged")

        let entries = WorkingAreaFiles.list(status)
        let untracked = entries.filter { $0.group == .untracked }.map(\.file.path)
        let stagedUntracked = try await ContinuousClock().measure {
            try await WorkingAreaStaging.stageUntracked(untracked, running: run)
        }
        report("staged \(untracked.count) untracked files", stagedUntracked)
        let stagedTracked = try await ContinuousClock().measure {
            try await WorkingAreaStaging.stageTracked(excluding: [], running: run)
        }
        report("staged the unstaged changes", stagedTracked)
        let (stagedStatus, stagedStatusDuration) = try await readStatus()
        report("status of \(WorkingAreaSummary(stagedStatus).description)", stagedStatusDuration)
        try await readWorkingArea(stagedStatus, "staged")

        let unstaged = try await ContinuousClock().measure {
            try await WorkingAreaStaging.unstageAll(running: run)
        }
        report("unstaged everything", unstaged)
        #expect(WorkingAreaSummary(try await readStatus().0) == summary)
        let stagedAll = try await ContinuousClock().measure {
            try await WorkingAreaStaging.stageAll(excluding: [], running: run)
        }
        report("staged everything at once", stagedAll)
        try await WorkingAreaStaging.unstageAll(running: run)
        #expect(WorkingAreaSummary(try await readStatus().0) == summary)
    }
}
