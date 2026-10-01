import Foundation

/// Where a review's window was left: the file shown, where each file was scrolled to, and how the
/// list was filtered, for when the review is opened again.
nonisolated struct ReviewPlace: Codable, Equatable, Sendable {
    var selection: String?
    var hidesChecked = false
    /// By path.
    var scrolls: [String: DiffScrollAnchor] = [:]
    var showsWholeDiff: Set<String> = []
}
