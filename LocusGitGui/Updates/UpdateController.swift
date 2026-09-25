import AppKit
import Sparkle

/// Owns the Sparkle updater.
final class UpdateController {
    private let updaterDelegate = UpdaterDelegate()
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
    }

    func start() {
        updaterController.startUpdater()
    }

    /// Sparkle's controller validates the item itself, disabling it while a check is running.
    func makeMenuItem() -> NSMenuItem {
        AppCommand.checkForUpdates.makeMenuItem(target: updaterController)
    }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    /// Beta items in the appcast are only offered to updaters that name the channel here.
    /// Everyone else sees the default channel alone.
    nonisolated func allowedChannels(for _: SPUUpdater) -> Set<String> {
        UpdateChannelPreference().allowedChannels
    }
}
