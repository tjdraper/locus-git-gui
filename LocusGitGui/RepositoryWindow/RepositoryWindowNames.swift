import Foundation

/// What each open repository is called in its tab and in the title bars of the windows opened from
/// it: its display name, or its folder name with enough parent folders to tell it from the other
/// open repositories. A name another open repository also goes by takes its folders too, in
/// parentheses after a display name, such as `Website (client/site)`.
nonisolated enum RepositoryWindowNames {
    struct Repository {
        let workTree: URL
        let displayName: String?
    }

    static func make(for repositories: [Repository]) -> [String] {
        let unnamed = repositories.indices.filter { repositories[$0].displayName == nil }
        let folderNames = Dictionary(uniqueKeysWithValues: zip(
            unnamed,
            DistinctFolderNames.make(for: unnamed.map { repositories[$0].workTree })
        ))
        var names = repositories.indices.map { repositories[$0].displayName ?? folderNames[$0] ?? "" }
        let clashes = Dictionary(grouping: names.indices) { names[$0].lowercased() }.values.filter { $0.count > 1 }
        for clash in clashes {
            let folders = DistinctFolderNames.make(for: clash.map { repositories[$0].workTree })
            for (index, folder) in zip(clash, folders) {
                names[index] = repositories[index].displayName.map { "\($0) (\(folder))" } ?? folder
            }
        }
        return names
    }
}
