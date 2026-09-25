import Foundation

/// Runs an executable to completion, streaming what it writes, and stops it when the caller stops
/// listening.
nonisolated struct ChildProcess: Sendable {
    enum Event: Sendable, Equatable {
        case standardOutput(Data)
        case standardError(Data)
        /// Always the last event, and only sent once both outputs have been read to the end.
        case exited(status: Int32)
    }

    struct Result: Sendable, Equatable {
        let status: Int32
        let standardOutput: Data
        let standardError: Data
    }

    enum Failure: Error {
        case couldNotStart(any Error)
    }

    /// Git cleans up its lock files on SIGTERM, so it gets the chance first. An interactive shell
    /// ignores SIGTERM, so anything still running after this long is killed.
    private static let terminationGracePeriod: DispatchTimeInterval = .seconds(2)

    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let currentDirectoryURL: URL?

    func run() async throws -> Result {
        var standardOutput = Data()
        var standardError = Data()
        for try await event in stream() {
            switch event {
            case let .standardOutput(data):
                standardOutput.append(data)
            case let .standardError(data):
                standardError.append(data)
            case let .exited(status):
                return Result(status: status, standardOutput: standardOutput, standardError: standardError)
            }
        }
        // The stream only ends without an exit when the task was cancelled.
        throw CancellationError()
    }

    /// Cancelling the task that iterates the stream, or dropping the stream, stops the process.
    func stream() -> AsyncThrowingStream<Event, any Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = environment
            process.currentDirectoryURL = currentDirectoryURL
            process.standardInput = FileHandle.nullDevice

            let standardOutput = Pipe()
            let standardError = Pipe()
            process.standardOutput = standardOutput
            process.standardError = standardError

            // A process can exit before its output has been read, so the exit is only reported once
            // the process has ended and both pipes have reached end of file.
            let finished = DispatchGroup()
            finished.enter()
            process.terminationHandler = { _ in finished.leave() }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: Failure.couldNotStart(error))
                return
            }

            finished.enter()
            Self.forward(standardOutput, as: { .standardOutput($0) }, to: continuation, then: finished)
            finished.enter()
            Self.forward(standardError, as: { .standardError($0) }, to: continuation, then: finished)

            finished.notify(queue: .global()) {
                continuation.yield(.exited(status: process.terminationStatus))
                continuation.finish()
            }

            continuation.onTermination = { termination in
                guard case .cancelled = termination else { return }
                // Something the process started can hold the pipes open after it is gone, and
                // nothing is listening any more.
                standardOutput.fileHandleForReading.readabilityHandler = nil
                standardError.fileHandleForReading.readabilityHandler = nil
                Self.stop(process)
            }
        }
    }

    private static func forward(
        _ pipe: Pipe,
        as event: @escaping @Sendable (Data) -> Event,
        to continuation: AsyncThrowingStream<Event, any Error>.Continuation,
        then finished: DispatchGroup
    ) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                finished.leave()
                return
            }
            continuation.yield(event(data))
        }
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let processIdentifier = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + terminationGracePeriod) {
            if process.isRunning {
                kill(processIdentifier, SIGKILL)
            }
        }
    }
}
