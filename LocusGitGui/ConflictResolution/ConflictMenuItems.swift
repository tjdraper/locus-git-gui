import AppKit

/// The conflict window's own commands, in the File, View and Commit menus only while a conflict
/// window is in front, since they act on the file it shows.
final class ConflictMenuItems {
    let fileItems: [NSMenuItem]
    let viewItems: [NSMenuItem]
    let commitItems: [NSMenuItem]
    private var watching: [Task<Void, Never>] = []

    init() {
        fileItems = [AppCommand.saveConflictResolution.makeMenuItem()]
        viewItems = [.separator(), AppCommand.showConflictBase.makeMenuItem()]
        commitItems = [.separator()] + [
            AppCommand.goToPreviousConflict,
            .goToNextConflict,
            .takeOurs,
            .takeTheirs,
            .takeBoth,
            .markConflictResolved,
        ].map { $0.makeMenuItem() }
        setShown(false)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            watching.append(Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    self?.setShown(NSApp.keyWindow?.windowController is ConflictWindowController)
                }
            })
        }
    }

    private func setShown(_ isShown: Bool) {
        for item in fileItems + viewItems + commitItems {
            item.isHidden = !isShown
        }
    }
}
