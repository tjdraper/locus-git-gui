import Foundation

nonisolated enum ResolvedPath {
    /// Follows every symbolic link. `resolvingSymlinksInPath()` deliberately stops short of
    /// resolving `/var` and `/tmp` to `/private`.
    static func of(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(filePath: String(cString: resolved))
    }
}
