/// The dashboard's command titles, which name how many repositories they act on, in the menu bar
/// and in a row's context menu alike.
nonisolated enum DashboardCommandTitle {
    static func open(_ count: Int) -> String {
        count > 1 ? "Open \(count) Repositories" : "Open Repository"
    }

    static func remove(_ count: Int) -> String {
        count > 1 ? "Remove \(count) Repositories from List" : "Remove Repository from List"
    }

    static let removeAllMissing = "Remove All Missing Repositories"
    static let setDisplayName = "Set Display Name…"
    static let showInFinder = "Show in Finder"
    static let showOnlyMissing = "Show Only Missing Repositories"
}
