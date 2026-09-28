import Foundation

/// A conflicted file as the conflict window shows it: its versions in the index, and the file in the
/// working tree with Git's markers in it, which is what's edited and saved.
nonisolated struct ConflictFileContents: Equatable, Sendable {
    enum Version: Equatable, Sendable {
        case text(String)
        /// Binary, or in an encoding other than UTF-8, which the window can't edit and save as it was.
        case notText
        case absent

        var text: String? {
            if case let .text(text) = self { text } else { nil }
        }
    }

    let path: String
    let stages: ConflictStages
    let base: Version
    let ours: Version
    let theirs: Version
    let result: Version
    let markerSize: Int

    /// Whether the conflict is resolved by editing the lines, rather than by choosing a version.
    var isEditable: Bool {
        stages.isAboutContent && ours.text != nil && theirs.text != nil && result.text != nil && base != .notText
    }

    static func read(
        _ path: String,
        workTree: URL,
        running run: (GitCommand) async throws -> ChildProcess.Result
    ) async throws -> ConflictFileContents {
        let stages = try await GitReadFailure.read("conflicts", with: ConflictStages.command(for: path), running: run) {
            try ConflictStages(parsing: $0)
        }
        let markerSize = try await readMarkerSize(path, running: run)
        let base = try await readVersion(stages.base, running: run)
        let ours = try await readVersion(stages.ours, running: run)
        let theirs = try await readVersion(stages.theirs, running: run)
        let result = await readWorkingTree(workTree.appending(path: path, directoryHint: .notDirectory))
        return ConflictFileContents(
            path: path,
            stages: stages,
            base: base,
            ours: ours,
            theirs: theirs,
            result: result,
            markerSize: markerSize
        )
    }

    private static func readVersion(
        _ version: ConflictStages.Version?,
        running run: (GitCommand) async throws -> ChildProcess.Result
    ) async throws -> Version {
        guard let version else { return .absent }
        guard !version.isSubmodule, !version.isSymbolicLink else { return .notText }
        let command = GitCommand.reading(["cat-file", "blob", version.object])
        let data = try await GitReadFailure.read("conflicts", with: command, running: run) { $0 }
        return await decode(data)
    }

    @concurrent
    private static func readWorkingTree(_ url: URL) async -> Version {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return .absent }
        guard !isFolder.boolValue, let data = try? Data(contentsOf: url) else { return .notText }
        return await decode(data)
    }

    /// Git takes a file with a NUL in its first 8,000 bytes for binary.
    @concurrent
    static func decode(_ data: Data) async -> Version {
        guard !data.prefix(8000).contains(0), let text = String(data: data, encoding: .utf8) else { return .notText }
        return .text(text)
    }

    /// From the file's `conflict-marker-size` attribute, printed as `<path> NUL <attribute> NUL <value> NUL`.
    private static func readMarkerSize(_ path: String, running run: (GitCommand) async throws -> ChildProcess.Result) async throws -> Int {
        let command = GitCommand.reading(["check-attr", "-z", "conflict-marker-size", "--", path])
        return try await GitReadFailure.read("attributes", with: command, running: run) { output in
            let fields = output.split(separator: 0, omittingEmptySubsequences: false)
            guard fields.count >= 3, let size = String(bytes: fields[2], encoding: .utf8).flatMap({ Int($0) }), size > 0 else {
                return ConflictMarkers.defaultMarkerSize
            }
            return size
        }
    }

    /// Over the file as it is, so it keeps its permissions, such as being executable. On the caller's
    /// thread, so a save as the app quits finishes before it does.
    static func save(_ text: String, to path: String, in workTree: URL) throws {
        try Data(text.utf8).write(to: workTree.appending(path: path, directoryHint: .notDirectory))
    }
}
