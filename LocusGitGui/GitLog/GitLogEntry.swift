import Foundation

/// One command the app ran in a repository, as the Git log shows it.
nonisolated struct GitLogEntry: Identifiable, Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case exited(ChildProcess.Result)
        case couldNotStart(String)
        case cancelled
    }

    /// A refresh of a large repository runs all day and can print thousands of files each time,
    /// so a successful command keeps only enough to see what it returned. A failure's output is
    /// what the log is read for, so it keeps far more.
    static let successfulOutputLimit = 4 * 1024
    static let failedOutputLimit = 64 * 1024

    let id = UUID()
    let startedAt: Date
    let executable: URL
    let arguments: [String]
    let duration: Duration
    let outcome: Outcome

    var commandLine: String {
        GitCommandLine.display(arguments)
    }

    var succeeded: Bool {
        if case let .exited(result) = outcome {
            result.status == 0
        } else {
            false
        }
    }

    var statusDescription: String {
        switch outcome {
        case let .exited(result):
            "exit \(result.status)"
        case .couldNotStart:
            "didn’t start"
        case .cancelled:
            "cancelled"
        }
    }

    /// Standard output, then standard error. Machine-readable output separates records with NUL,
    /// which is shown as a line break so it can be read.
    var output: String {
        switch outcome {
        case let .exited(result):
            [result.standardOutput, result.standardError]
                .map { Self.readable($0, limit: result.status == 0 ? Self.successfulOutputLimit : Self.failedOutputLimit) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        case let .couldNotStart(reason):
            reason
        case .cancelled:
            ""
        }
    }

    var durationDescription: String {
        "\(Self.milliseconds(duration)) ms"
    }

    var transcript: String {
        let started = startedAt.formatted(.iso8601.time(includingFractionalSeconds: true))
        let header = "[\(started)] $ \(commandLine)  (\(statusDescription), \(durationDescription))"
        return output.isEmpty ? header : header + "\n" + output
    }

    private static func readable(_ data: Data, limit: Int) -> String {
        // Cutting at a byte count can split a character, and a replacement character at the cut is
        // better in a log than losing the whole output to a failed decode.
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: data.prefix(limit), as: UTF8.self)
            .replacingOccurrences(of: "\0", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return data.count > limit ? text + "\n… (\(data.count - limit) more bytes not kept)" : text
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
