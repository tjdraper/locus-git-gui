import os

/// Reads the changes of a file that were left out of a diff for their size, once the user asks for
/// them, and keeps what went wrong when that fails so Show Details can say.
final class LeftOutChangesReader {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "DiffView")

    var read: ((ChangedFile) async throws -> DiffFile)?
    private var tasks: [String: Task<Void, Never>] = [:]
    private var failures: [String: GitFailure] = [:]

    var canRead: Bool {
        read != nil
    }

    func failure(for path: String) -> GitFailure? {
        failures[path]
    }

    /// Hands back the file, or a summary of why it couldn't be read. Nothing is handed back once
    /// `cancelAll` has been called.
    func start(_ file: ChangedFile, completion: @escaping (Result<DiffFile, Failed>) -> Void) {
        guard let read else { return }
        failures[file.path] = nil
        tasks[file.path]?.cancel()
        tasks[file.path] = Task { [weak self] in
            do {
                let read = try await read(file)
                guard !Task.isCancelled else { return }
                completion(.success(read))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                completion(.failure(Failed(summary: summarize(error, path: file.path))))
            }
        }
    }

    struct Failed: Error {
        let summary: String
    }

    func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks = [:]
        failures = [:]
    }

    private func summarize(_ error: any Error, path: String) -> String {
        guard let failure = error as? GitReadFailure else {
            Self.log.error("Reading a file's changes failed: \(String(describing: type(of: error)), privacy: .public)")
            return "This file’s changes couldn’t be read."
        }
        let summary = failure.outputWasUnreadable
            ? "Locus Git Gui couldn’t read Git’s report on this file’s changes."
            : "Git couldn’t read this file’s changes."
        failures[path] = GitFailure(summary: summary, arguments: failure.command.arguments, result: failure.result)
        return summary
    }
}
