import os

/// Reads the changes of a file that were left out of a diff for their size, once the user asks for
/// them, and keeps what went wrong when that fails so Show Details can say.
final class LeftOutChangesReader {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "DiffView")

    var read: ((DiffFile) async throws -> DiffFile)?
    private var tasks: [DiffFile.Identity: Task<Void, Never>] = [:]
    private var failures: [DiffFile.Identity: GitFailure] = [:]

    var canRead: Bool {
        read != nil
    }

    func failure(for file: DiffFile.Identity) -> GitFailure? {
        failures[file]
    }

    /// Hands back the file, or a summary of why it couldn't be read. Nothing is handed back once
    /// `cancelAll` has been called.
    func start(_ file: DiffFile, completion: @escaping (Result<DiffFile, Failed>) -> Void) {
        guard let read else { return }
        failures[file.id] = nil
        tasks[file.id]?.cancel()
        tasks[file.id] = Task { [weak self] in
            do {
                let read = try await read(file)
                guard !Task.isCancelled else { return }
                completion(.success(read))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                completion(.failure(Failed(summary: summarize(error, file: file.id))))
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

    private func summarize(_ error: any Error, file: DiffFile.Identity) -> String {
        guard let failure = error as? GitReadFailure else {
            Self.log.error("Reading a file's changes failed: \(String(describing: type(of: error)), privacy: .public)")
            return "This file’s changes couldn’t be read."
        }
        let summary = failure.outputWasUnreadable
            ? "Locus Git Gui couldn’t read Git’s report on this file’s changes."
            : "Git couldn’t read this file’s changes."
        failures[file] = GitFailure(summary: summary, arguments: failure.command.arguments, result: failure.result)
        return summary
    }
}
