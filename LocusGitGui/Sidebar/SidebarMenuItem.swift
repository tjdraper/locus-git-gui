/// A command in a sidebar row's context menu, titled for that row, such as “Merge “feature” into
/// “main””.
struct SidebarMenuItem: Identifiable {
    let title: String
    var isEnabled = true
    let action: () -> Void

    var id: String {
        title
    }
}
