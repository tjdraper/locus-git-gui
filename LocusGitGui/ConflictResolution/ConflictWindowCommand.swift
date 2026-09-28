import AppKit

/// View > Show Conflicts, which opens the repository's conflict window from any of its windows while
/// it has files with conflicts, or brings the window forward while it's open.
final class ConflictWindowCommand: NSObject, NSMenuItemValidation {
    static let actions: Set<Selector> = [#selector(showConflicts(_:))]

    private let canShow: () -> Bool
    private let show: () -> Void

    init(canShow: @escaping () -> Bool, show: @escaping () -> Void) {
        self.canShow = canShow
        self.show = show
    }

    @objc func showConflicts(_: Any?) {
        guard canShow() else {
            NSSound.beep()
            return
        }
        show()
    }

    func validateMenuItem(_: NSMenuItem) -> Bool {
        canShow()
    }
}
