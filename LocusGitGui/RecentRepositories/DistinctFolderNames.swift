import Foundation

/// Names for a set of folders, each its folder name with just enough parent folders to tell it apart
/// from the others, such as `client/app` and `server/app`.
nonisolated enum DistinctFolderNames {
    static func make(for folders: [URL]) -> [String] {
        let paths = folders.map { $0.standardizedFileURL.pathComponents.filter { $0 != "/" } }
        return paths.indices.map { index in
            let components = paths[index]
            for depth in components.indices.map({ $0 + 1 }) {
                let suffix = components.suffix(depth)
                let isShared = paths.indices.contains { $0 != index && paths[$0].suffix(depth) == suffix }
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
