import Foundation

/// The real `git` the tests run, and scratch folders for it to run in.
enum TestGit {
    /// Homebrew's Git first, since Apple's has no translations and can't show that Git's messages
    /// are read in English.
    static let executableURL: URL = {
        let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
        let path = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git"
        return URL(filePath: path)
    }()

    static func runner(environment: [String: String] = ProcessInfo.processInfo.environment) -> GitRunner {
        GitRunner(executableURL: executableURL, environment: environment)
    }

    static func makeScratchFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "LocusGitGuiTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return ResolvedPath.of(folder)
    }
}
