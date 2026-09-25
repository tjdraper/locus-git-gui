import AppKit

/// Offers, once, to move the app into `/Applications` when it is running from anywhere else.
///
/// Apps opened straight out of Downloads run from a read-only randomized copy, which breaks
/// Sparkle updates.
struct ApplicationsFolderMoveWorkflow {
    private static let declinedDefaultsKey = "DeclinedMoveToApplicationsFolder"

    /// Debug builds run from DerivedData, so the move would be offered on every launch.
    static var isAvailable: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    let location = AppBundleLocation.current()

    func offerIfNeeded() {
        guard shouldOffer else { return }

        NSApp.activate()
        guard askToMove() else {
            UserDefaults.standard.set(true, forKey: Self.declinedDefaultsKey)
            return
        }

        move()
    }

    func move() {
        do {
            try ApplicationsFolderMover(location: location).moveAndRelaunch()
        } catch {
            reportFailure(error)
        }
    }

    private var shouldOffer: Bool {
        Self.isAvailable
            && !location.isInApplicationsFolder
            && !UserDefaults.standard.bool(forKey: Self.declinedDefaultsKey)
    }

    private func askToMove() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Move Locus Git Gui to your Applications folder?"
        alert.informativeText = location.isTranslocated
            ? """
            macOS is running Locus Git Gui from a temporary read-only copy, so it can’t update \
            itself. Moving it to Applications fixes that.
            """
            : """
            Locus Git Gui can’t update itself reliably from its current location. Moving it to \
            Applications fixes that.
            """
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func reportFailure(_ error: any Error) {
        let alert = NSAlert()
        alert.messageText = "Locus Git Gui couldn’t move itself."
        alert.informativeText = """
        \(error.localizedDescription)

        Quit Locus Git Gui and drag it into your Applications folder in Finder.
        """
        alert.alertStyle = .warning
        alert.runModal()
    }
}
