/// Something that can be done to a file, a group of files or a hunk in a diff, such as staging it.
/// Whoever shows the diff decides what these are; the diff only shows them as buttons and menu items.
struct DiffAction {
    let title: String
    /// Longer, for a menu where the button's context is missing, such as Stage File for Stage.
    var menuTitle: String?
    var isEnabled = true
    var toolTip: String?
    /// Shown as a checkbox ticked or not, rather than a button, when set.
    var isOn: Bool?
    /// Only in the file's menu, not as a button on its header.
    var isInMenuOnly = false
    let perform: () -> Void
}
