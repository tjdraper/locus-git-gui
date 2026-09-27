import Foundation
import Testing

/// Times what every refresh reads for the sidebar, and the palette's search over every branch and
/// tag, against a repository with thousands of each. Skipped unless `LOCUS_PERFORMANCE_REPOSITORY`
/// names one. See Scripts/README.md.
@Suite(.enabled(if: PerformanceRepository.url != nil), .serialized)
struct SidebarPerformanceTests {
    private let runner = GitRunner(executableURL: TestGit.executableURL, environment: ProcessInfo.processInfo.environment)

    private func run(_ command: GitCommand) async throws -> ChildProcess.Result {
        try await runner.run(command, in: #require(PerformanceRepository.url))
    }

    /// Appended to a file beside the repository, since a test's printed output doesn't reach
    /// `xcodebuild`.
    private func report(_ what: String, _ duration: Duration) {
        guard let repository = PerformanceRepository.url else { return }
        let file = repository.deletingLastPathComponent().appending(path: repository.lastPathComponent + "-performance.txt")
        let time = duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))
        let line = "\(Date().formatted(.iso8601)) \(what): \(time)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    @Test
    func refreshReadsTheSidebar() async throws {
        // Arrange
        let clock = ContinuousClock()
        var output = Data()
        var refs: [Ref] = []
        var contents: SidebarContents?

        // Act
        let reading = try await clock.measure {
            output = try await run(Ref.listCommand).standardOutput
        }
        let parsing = try clock.measure {
            refs = try Ref.parseList(output)
        }
        let listing = try await clock.measure {
            contents = try await SidebarContents.read(refs: refs, running: run)
        }
        let reusing = try await clock.measure {
            _ = try await Ref.readList(reusingCountsFrom: refs, running: run)
        }

        // Assert
        report("read \(refs.count) refs", reading)
        report("parse \(refs.count) refs", parsing)
        report("remotes, stashes and sorting for the sidebar", listing)
        report("read again with nothing moved, reusing the counts", reusing)
        #expect(contents?.branches.isEmpty == false)
    }

    @Test
    func filteringAndPinningKeepUp() async throws {
        // Arrange
        let refs = try await Ref.readList(running: run)
        let contents = try await SidebarContents.read(refs: refs, running: run)
        let pins = SidebarPins(Array(contents.branches.prefix(20).map(\.id)))
        let clock = ContinuousClock()

        // Act
        let pinning = clock.measure {
            _ = contents.pinning(pins)
        }
        let filtering = clock.measure {
            _ = contents.filtered(by: "branch-1")
        }
        let rows = clock.measure {
            _ = contents.visibleRows(collapsedSections: [], collapsedRemotes: [])
        }

        // Assert
        report("pinning 20", pinning)
        report("filtering", filtering)
        report("visible rows", rows)
    }

    @Test
    func goToBranchSearchesEveryBranch() async throws {
        // Arrange
        let refs = try await Ref.readList(running: run)
        let contents = try await SidebarContents.read(refs: refs, running: run)
        let remoteNames = contents.remotes.flatMap { remote in remote.branches.map { remote.name + "/" + $0.name } }
        let names = contents.branches.map(\.name) + remoteNames
        let items = names.map { CommandPaletteItem(id: $0, title: $0, detail: "Branch", shortcut: nil, isListedBeforeTyping: true) }
        let history = SearchPickHistory()
        let clock = ContinuousClock()
        var search: CommandPaletteSearch?

        // Act
        let preparing = clock.measure {
            search = CommandPaletteSearch(items: items)
        }
        let ranking = clock.measure {
            _ = search?.rank("b12", history: history, at: .now)
        }

        // Assert
        report("preparing Go to Branch over \(items.count)", preparing)
        report("ranking a search over \(items.count)", ranking)
    }
}
