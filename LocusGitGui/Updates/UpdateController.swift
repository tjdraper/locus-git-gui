import AppKit
import Sparkle

/// Owns the Sparkle updater, and the settings and menu items that belong to it.
@Observable
final class UpdateController: NSObject, NSMenuItemValidation {
    @ObservationIgnored private let reminder: UpdateReminder
    @ObservationIgnored private let updaterDelegate: UpdaterDelegate
    @ObservationIgnored private let updaterController: SPUStandardUpdaterController
    /// Shown only while an update is waiting (see `UpdateReminder`).
    @ObservationIgnored private lazy var installItem = AppCommand.installWaitingUpdate.makeMenuItem(target: self)
    @ObservationIgnored private var automaticChecksObservation: NSKeyValueObservation?

    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return updaterController.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                updaterController.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    var receivesBetaUpdates: Bool {
        get {
            access(keyPath: \.receivesBetaUpdates)
            return UpdateChannelPreference().receivesBetaUpdates
        }
        set {
            withMutation(keyPath: \.receivesBetaUpdates) {
                UpdateChannelPreference().receivesBetaUpdates = newValue
            }
        }
    }

    var isRunningBeta: Bool {
        UpdateChannelPreference().isRunningBeta
    }

    override init() {
        let reminder = UpdateReminder()
        let updaterDelegate = UpdaterDelegate(reminder: reminder)
        self.reminder = reminder
        self.updaterDelegate = updaterDelegate
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: reminder
        )
        super.init()
        reminder.onChange = { [weak self] in self?.showReminder() }
        showReminder()
        // Sparkle's own prompt, which installs from before the checklist still see, sets it too.
        automaticChecksObservation = updaterController.updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in
            // Sparkle changes it on the main thread, so the observer fires there too.
            MainActor.assumeIsolated {
                self?.withMutation(keyPath: \.automaticallyChecksForUpdates) {
                    // Sparkle already holds the new value; this only tells SwiftUI.
                }
            }
        }
    }

    func start() {
        updaterController.startUpdater()
    }

    /// Install Update… and Check for Updates…, for the app menu.
    func makeMenuItems() -> [NSMenuItem] {
        [installItem, AppCommand.checkForUpdates.makeMenuItem(target: self)]
    }

    /// Turns automatic checks on unless the user already chose, which is what Sparkle's own prompt
    /// suggests. Once a choice is stored, Sparkle never shows that prompt.
    func defaultToAutomaticChecks() {
        guard UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") == nil else { return }
        automaticallyChecksForUpdates = true
    }

    /// Also brings a waiting update's window forward, which Sparkle shows without activating the app.
    @objc func checkForUpdates(_: Any?) {
        reminder.userWillCheckForUpdates()
        NSApp.activate()
        updaterController.checkForUpdates(nil)
    }

    @objc func installWaitingUpdate(_ sender: Any?) {
        checkForUpdates(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(checkForUpdates(_:)), #selector(installWaitingUpdate(_:)):
            updaterController.updater.canCheckForUpdates
        default:
            true
        }
    }

    /// A menu item for any update waiting, and a badge on the Dock icon for one the user hasn't
    /// seen yet, as System Settings badges its own for a macOS update.
    private func showReminder() {
        if let version = reminder.waitingVersion {
            installItem.title = "Install Update \(version)…"
            installItem.isHidden = false
        } else {
            installItem.isHidden = true
        }
        NSApp.dockTile.badgeLabel = reminder.hasUnseenUpdate ? "1" : nil
    }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private let reminder: UpdateReminder

    init(reminder: UpdateReminder) {
        self.reminder = reminder
    }

    /// Beta items in the appcast are only offered to updaters that name the channel here.
    /// Everyone else sees the default channel alone.
    nonisolated func allowedChannels(for _: SPUUpdater) -> Set<String> {
        UpdateChannelPreference().allowedChannels
    }

    /// The setup checklist asks instead, so a fresh install isn't asked twice. Installs from before
    /// the checklist never see it, so Sparkle still asks them.
    nonisolated func updaterShouldPromptForPermissionToCheck(forUpdates _: SPUUpdater) -> Bool {
        FirstRunStatus().state == .existingInstall
    }

    nonisolated func updater(
        _: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state _: SPUUserUpdateState
    ) {
        let version = updateItem.displayVersionString
        // Sparkle calls its delegates on the main thread.
        MainActor.assumeIsolated {
            reminder.userDidMake(choice, forVersion: version)
        }
    }
}
