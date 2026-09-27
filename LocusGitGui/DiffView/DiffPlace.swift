/// Where the user left a diff: which files are collapsed and which are picked, the file the keyboard
/// marked as current, and where it was scrolled to.
nonisolated struct DiffPlace: Codable, Equatable, Sendable {
    var collapsed: Set<DiffFile.Identity> = []
    var picked: Set<DiffFile.Identity> = []
    /// Where Shift-click and Shift-J/K take in a range from.
    var pickAnchor: DiffFile.Identity?
    var marked: DiffFile.Identity?
    /// Nil at the very top, where every diff starts.
    var scroll: DiffScrollAnchor?
}
