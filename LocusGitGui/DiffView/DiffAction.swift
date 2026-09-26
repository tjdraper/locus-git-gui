/// Something that can be done to a file, a group of files or a hunk in a diff, such as staging it.
/// Whoever shows the diff decides what these are; the diff only shows them as buttons and menu items.
struct DiffAction {
    let title: String
    /// Longer, for a menu where the button's context is missing, such as Stage File for Stage.
    var menuTitle: String?
    var isEnabled = true
    var toolTip: String?
    let perform: () -> Void
}
