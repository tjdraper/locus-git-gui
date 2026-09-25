import Foundation
import Testing

struct ChildProcessTests {
    private func shell(_ script: String) -> ChildProcess {
        ChildProcess(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: ["-c", script],
            environment: ProcessInfo.processInfo.environment,
            currentDirectoryURL: nil
        )
    }

    private func waitUntilGone(_ processIdentifier: pid_t) async throws -> Bool {
        for _ in 0 ..< 50 {
            if kill(processIdentifier, 0) != 0 {
                return true
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    /// Returning from inside the loop drops the stream, the same as a caller that stops listening.
    private func processIdentifierThenStopListening(to process: ChildProcess) async throws -> pid_t {
        for try await event in process.stream() {
            if case let .standardOutput(data) = event {
                let line = String(bytes: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return try #require(line.flatMap { pid_t($0) })
            }
        }
        Issue.record("The process wrote nothing")
        return 0
    }

    @Test
    func collectsBothOutputsAndTheExitStatus() async throws {
        // Arrange
        let process = shell("printf out; printf err >&2; exit 3")

        // Act
        let result = try await process.run()

        // Assert
        #expect(result.status == 3)
        #expect(result.standardOutput == Data("out".utf8))
        #expect(result.standardError == Data("err".utf8))
    }

    @Test
    func readsOutputLargerThanAPipeBuffer() async throws {
        // Arrange
        let process = shell("head -c 1000000 /dev/zero")

        // Act
        let result = try await process.run()

        // Assert
        #expect(result.status == 0)
        #expect(result.standardOutput.count == 1_000_000)
    }

    @Test
    func anExecutableThatIsMissingCantStart() async {
        // Arrange
        let process = ChildProcess(
            executableURL: URL(filePath: "/nonexistent/git"),
            arguments: [],
            environment: [:],
            currentDirectoryURL: nil
        )

        // Act & Assert
        await #expect(throws: ChildProcess.Failure.self) {
            try await process.run()
        }
    }

    @Test
    func cancellingTheTaskThrowsCancellation() async throws {
        // Arrange
        let task = Task { try await shell("exec sleep 30").run() }
        try await Task.sleep(for: .milliseconds(200))
        let started = ContinuousClock.now

        // Act
        task.cancel()

        // Assert
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test
    func droppingTheStreamStopsTheProcess() async throws {
        // Arrange
        let process = shell("echo $$; exec sleep 30")

        // Act
        let processIdentifier = try await processIdentifierThenStopListening(to: process)

        // Assert
        #expect(try await waitUntilGone(processIdentifier))
    }

    @Test
    func aProcessThatIgnoresTerminationIsKilled() async throws {
        // Arrange
        let process = shell("trap '' TERM; echo $$; while :; do sleep 0.1; done")

        // Act
        let processIdentifier = try await processIdentifierThenStopListening(to: process)

        // Assert
        #expect(try await waitUntilGone(processIdentifier))
    }
}
