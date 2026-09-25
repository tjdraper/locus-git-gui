import Foundation

/// Names for a set of folders, each its folder name with just enough parent folders to tell it apart
/// from the others, such as `client/app` and `server/app`.
nonisolated enum DistinctFolderNames {
    static func make(for folders: [URL]) -> [String] {
        let paths = folders.map { $0.standardizedFileURL.pathComponents.filter { $0 != "/" } }
        // Only folders with the same name need comparing, which keeps a long list quick to name.
        let sameName = Dictionary(grouping: paths.indices) { paths[$0].last ?? "" }
        return paths.indices.map { index in
            let components = paths[index]
            let others = (sameName[components.last ?? ""] ?? []).filter { $0 != index }
            for depth in components.indices.map({ $0 + 1 }) {
                let suffix = components.suffix(depth)
                let isShared = others.contains { paths[$0].suffix(depth) == suffix }
                if !isShared {
                    return suffix.joined(separator: "/")
                }
            }
            // Every parent folder is shared, so one path ends with the whole of this one, such as
            // `/app` and `/client/app`.
            return (folders[index].standardizedFileURL.path as NSString).abbreviatingWithTildeInPath
        }
    }
}
