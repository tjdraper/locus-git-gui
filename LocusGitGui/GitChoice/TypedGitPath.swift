import Foundation

/// A path typed or pasted into the Git step. Paths copied from Terminal often arrive quoted or with
/// escaped spaces, and paths copied from a document with a trailing newline.
nonisolated enum TypedGitPath {
    /// Nil unless the text is a full path, since a relative one would depend on the folder the app
    /// happens to be running in.
    static func url(from text: String) -> URL? {
        var path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.count >= 2, let first = path.first, first == path.last, first == "'" || first == "\"" {
            path = String(path.dropFirst().dropLast())
        } else {
            path = path.replacingOccurrences(of: "\\ ", with: " ")
        }
        path = (path as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else {
            return nil
        }
        return URL(filePath: path)
    }
}
