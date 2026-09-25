import Foundation

/// Apple's `/usr/bin/git` is a shim that runs the Git in Xcode or the Command Line Tools. With
/// neither installed, running it throws up macOS's own install dialog, so the app checks first and
/// never runs the shim without them.
nonisolated enum CommandLineTools {
    static let shimmedGit = URL(filePath: "/usr/bin/git")

    /// `xcode-select` honors `DEVELOPER_DIR`, as the shim does, so it gets the user's environment.
    /// It can name a folder that has since been deleted, which is why the Git inside is checked too.
    static func areInstalled(environment: [String: String]) async -> Bool {
        let process = ChildProcess(
            executableURL: URL(filePath: "/usr/bin/xcode-select"),
            arguments: ["--print-path"],
            environment: environment,
            currentDirectoryURL: nil
        )
        guard let result = try? await process.run(),
              result.status == 0,
              let developerDirectory = String(bytes: result.standardOutput, encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              !developerDirectory.isEmpty
        else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: developerDirectory + "/usr/bin/git")
    }

    static func isShim(_ url: URL) -> Bool {
        ResolvedPath.of(url) == shimmedGit
    }
}
