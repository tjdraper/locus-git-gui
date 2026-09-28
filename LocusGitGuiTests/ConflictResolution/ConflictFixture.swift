import Foundation

/// Repositories stopped partway through a merge, the way the conflict window finds them.
extension FixtureRepository {
    /// `main` and `feature` each change `path` from `base`, and merging `feature` into `main` stops
    /// on the conflict. `extra` is passed to `git merge`, such as a conflict style.
    static func mergeStoppedOnConflict(
        path: String = "notes.txt",
        base: String,
        main: String,
        feature: String,
        mergeOptions extra: [String] = []
    ) async throws -> FixtureRepository {
        let repository = try await make()
        try await repository.commit("Base", writing: base, to: path)
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("Feature", writing: feature, to: path)
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("Main", writing: main, to: path)
        let result = try await repository.run(.changing(extra + ["merge", "--no-edit", "feature"]))
        guard result.status != 0 else {
            throw GitFailed(arguments: ["merge", "feature"], result: result)
        }
        return repository
    }

    func conflictContents(_ path: String) async throws -> ConflictFileContents {
        try await ConflictFileContents.read(path, workTree: folder) { try await run($0) }
    }
}
