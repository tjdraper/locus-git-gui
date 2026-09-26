import Foundation

/// Reads a fixture repository's working area the way the app does.
extension FixtureRepository {
    func status() async throws -> RepositoryStatus {
        let result = try await run(RepositoryStatus.command)
        return try RepositoryStatus(parsing: result.standardOutput)
    }

    func workingArea(options: DiffOptions = DiffOptions()) async throws -> [DiffFile] {
        try await WorkingAreaDiff.read(status(), options: options, workTree: folder, readingPatch: readPatch)
    }

    func readPatch(_ command: GitCommand, _ limits: PatchParser.Limits) async throws -> (result: ChildProcess.Result, files: [FilePatch]) {
        let result = try await run(command)
        var parser = PatchParser(limits: limits)
        parser.consume(result.standardOutput)
        return (result, parser.finish())
    }

    /// The file as it's staged, byte for byte.
    func staged(_ path: String) async throws -> String {
        let result = try await run(.reading(["show", ":" + path]))
        return String(bytes: result.standardOutput, encoding: .utf8) ?? ""
    }

    func contents(of path: String) throws -> String {
        try String(contentsOf: folder.appending(path: path), encoding: .utf8)
    }

    func writeBytes(_ text: String, to path: String) throws {
        try Data(text.utf8).write(to: folder.appending(path: path))
    }
}
