import Foundation

/// Looks for `git` where Terminal would find it first, then in the usual places.
nonisolated enum GitFinder {
    struct Result: Equatable, Sendable {
        /// In the order found, so the first is the one Terminal runs.
        let installations: [GitInstallation]
        /// The Git that running `git` in Terminal starts, when one is on the search path.
        let terminalExecutableURL: URL?
        let commandLineToolsAreMissing: Bool
    }

    /// Homebrew on Apple silicon, then Homebrew on Intel and most other installers.
    private static let usualDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    static func find(environment: [String: String]) async -> Result {
        let toolsInstalled = await CommandLineTools.areInstalled(environment: environment)
        let paths = candidates(
            searchPath: environment["PATH"],
            includesShim: toolsInstalled,
            isExecutable: FileManager.default.isExecutableFile(atPath:),
            resolve: ResolvedPath.of
        )

        var installations: [GitInstallation] = []
        for path in paths {
            if let installation = try? await GitInstallation.probe(path, environment: environment) {
                installations.append(installation)
            }
        }
        let searchDirectories = absoluteDirectories(in: environment["PATH"])
        let terminalGit = installations.first { searchDirectories.contains($0.executableURL.deletingLastPathComponent().path) }
        return Result(
            installations: installations,
            terminalExecutableURL: terminalGit?.executableURL,
            commandLineToolsAreMissing: !toolsInstalled
        )
    }

    /// Two paths to the same executable count once, under the first path found. That is usually a
    /// link such as `/opt/homebrew/bin/git`, which keeps working after an upgrade moves the real
    /// file it points to.
    static func candidates(
        searchPath: String?,
        includesShim: Bool,
        isExecutable: (String) -> Bool,
        resolve: (URL) -> URL
    ) -> [URL] {
        let shimDirectory = CommandLineTools.shimmedGit.deletingLastPathComponent().path
        let directories = absoluteDirectories(in: searchPath) + usualDirectories + [shimDirectory]

        var seen: Set<URL> = []
        var candidates: [URL] = []
        for directory in directories {
            let url = URL(filePath: directory).appending(path: "git")
            guard isExecutable(url.path) else { continue }
            let resolved = resolve(url)
            if resolved == CommandLineTools.shimmedGit, !includesShim {
                continue
            }
            if seen.insert(resolved).inserted {
                candidates.append(url)
            }
        }
        return candidates
    }

    /// A relative entry such as `.` depends on the folder a command runs in, which for the app is
    /// a repository, so it is never where Git comes from.
    private static func absoluteDirectories(in searchPath: String?) -> [String] {
        (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
    }
}
