import Foundation
import Testing

/// Times the conflict window's reading against a repository made with
/// `Scripts/GenerateTestRepository.swift --conflicts <n>`, which leaves a merge stopped on thousands
/// of files and on one very large file. Skipped unless `LOCUS_PERFORMANCE_REPOSITORY` names one.
/// Changes nothing. See Scripts/README.md.
@Suite(.enabled(if: PerformanceRepository.url != nil), .serialized)
struct ConflictPerformanceTests {
    private static let largeFile = "conflicts/large.txt"
    private let runner = GitRunner(executableURL: TestGit.executableURL, environment: ProcessInfo.processInfo.environment)

    private func run(_ command: GitCommand) async throws -> ChildProcess.Result {
        try await runner.run(command, in: #require(PerformanceRepository.url))
    }

    private func report(_ what: String, _ duration: Duration) {
        guard let repository = PerformanceRepository.url else { return }
        let file = repository.deletingLastPathComponent().appending(path: repository.lastPathComponent + "-performance.txt")
        let formatted = duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))
        let line = "\(Date().formatted(.iso8601)) conflicts: \(what): \(formatted)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    @Test
    func thousandsOfConflictedFilesAreListed() async throws {
        var status: RepositoryStatus?
        let duration = try await ContinuousClock().measure {
            status = try RepositoryStatus(parsing: try await run(RepositoryStatus.command).standardOutput)
        }
        let conflicted = try #require(status).files.count { if case .conflicted = $0.state { true } else { false } }
        report("status listing \(conflicted) conflicted files", duration)
        #expect(conflicted >= 1)
    }

    @Test
    func aVeryLargeFileIsReadAndItsConflictsFound() async throws {
        let workTree = try #require(PerformanceRepository.url)
        var contents: ConflictFileContents?
        let read = try await ContinuousClock().measure {
            contents = try await ConflictFileContents.read(Self.largeFile, workTree: workTree) { try await run($0) }
        }
        let file = try #require(contents)
        let result = try #require(file.result.text)
        report("reading \(Self.largeFile), \(result.utf8.count) bytes", read)

        var markers = ConflictMarkers(parsing: "")
        let found = ContinuousClock().measure {
            markers = ConflictMarkers(parsing: result, markerSize: file.markerSize)
        }
        report("finding its \(markers.conflicts.count) conflicts", found)

        let ours = try #require(file.ours.text)
        let theirs = try #require(file.theirs.text)
        var locators: [ConflictSideLocator] = []
        let indexing = ContinuousClock().measure {
            locators = [ConflictSideLocator(file: ours), ConflictSideLocator(file: theirs)]
        }
        report("indexing both sides' lines", indexing)
        var located: [Range<Int>?] = []
        let locating = ContinuousClock().measure {
            located = locators[0].locate(.ours, of: markers, in: result) + locators[1].locate(.theirs, of: markers, in: result)
        }
        report("locating the conflicts in both sides", locating)

        var taken = ""
        let taking = ContinuousClock().measure {
            let text = result as NSString
            taken = text.replacingCharacters(
                in: markers.conflicts[0].range,
                with: ConflictMarkers.resolution(of: markers.conflicts[0], in: text, choosing: .ours)
            )
            markers = ConflictMarkers(parsing: taken, markerSize: file.markerSize)
        }
        report("taking a side and finding the conflicts again", taking)
        #expect(located.allSatisfy { $0?.isEmpty == false })
        #expect(!markers.conflicts.isEmpty)
    }
}
