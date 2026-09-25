import Foundation

/// A `git` executable that answered `--version` like Git does.
nonisolated struct GitInstallation: Equatable, Sendable {
    enum ProbeFailure: Error, Equatable {
        case notExecutable
        case commandLineToolsMissing
        case couldNotRun
        case notGit
    }

    let executableURL: URL
    /// As Git prints it, such as `2.54.0 (Apple Git-157)`.
    let version: String

    static func probe(_ url: URL, environment: [String: String]) async throws(ProbeFailure) -> GitInstallation {
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw .notExecutable
        }
        if CommandLineTools.isShim(url), await !CommandLineTools.areInstalled(environment: environment) {
            throw .commandLineToolsMissing
        }

        let runner = GitRunner(executableURL: url, environment: environment)
        let result: ChildProcess.Result
        do {
            result = try await runner.run(.reading(["--version"]), in: FileManager.default.homeDirectoryForCurrentUser)
        } catch {
            throw .couldNotRun
        }
        guard result.status == 0, let version = version(from: result.standardOutput) else {
            throw .notGit
        }
        return GitInstallation(executableURL: url, version: version)
    }

    /// Whether a Git chosen earlier can still run: it hasn't been deleted, and if it is Apple's
    /// shim, the Command Line Tools behind it haven't been removed.
    static func isUsable(_ url: URL, environment: [String: String]) async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            return false
        }
        guard CommandLineTools.isShim(url) else {
            return true
        }
        return await CommandLineTools.areInstalled(environment: environment)
    }

    static func version(from output: Data) -> String? {
        let prefix = "git version "
        guard let text = String(bytes: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.hasPrefix(prefix),
              text.count > prefix.count
        else {
            return nil
        }
        return String(text.dropFirst(prefix.count))
    }
}
