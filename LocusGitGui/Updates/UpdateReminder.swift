import Sparkle

/// Keeps an update found by a scheduled check from interrupting, even just after launch, since the
/// user opened the app to do something else. The update waits behind the dashboard's and the
/// repository windows' Update Available button, the app menu and the Dock badge until the user asks
/// to see it, or until it has waited two weeks (`UpdateNagClock`).
/// https://sparkle-project.org/documentation/gentle-reminders
final class UpdateReminder: NSObject, SPUStandardUserDriverDelegate {
    var onChange: (() -> Void)?

    var waitingVersion: String? {
        scheduledVersion ?? dismissedVersion
    }

    var hasUnseenUpdate: Bool {
        scheduledVersion != nil
    }

    /// Found by a scheduled check, and held by Sparkle until the user looks at it.
    private var scheduledVersion: String? {
        didSet { if scheduledVersion != oldValue { onChange?() } }
    }

    /// Seen and put off. Sparkle ends its session and forgets the update, so the sign starts a new
    /// check, which shows the window again.
    private var dismissedVersion: String? {
        didSet { if dismissedVersion != oldValue { onChange?() } }
    }

    /// Called by the updater's delegate, just before Sparkle ends the session.
    func userDidMake(_ choice: SPUUserUpdateChoice, forVersion version: String) {
        dismissedVersion = choice == .dismiss ? version : nil
        if choice == .skip {
            noUpdateWaiting()
        }
    }

    /// Called by the updater's delegate when a check finds nothing to install, as after the update
    /// was installed or skipped.
    func noUpdateWaiting() {
        scheduledVersion = nil
        dismissedVersion = nil
        UpdateAvailability.shared.clear()
        UpdateNagClock().reset()
    }

    /// The check finds the update again if it's still there, and shows it.
    func userWillCheckForUpdates() {
        scheduledVersion = nil
        dismissedVersion = nil
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem,
        andInImmediateFocus _: Bool
    ) -> Bool {
        UpdateNagClock().isOverdue()
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state _: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        onMain {
            UpdateNagClock().noteFound()
            UpdateAvailability.shared.showFound(version)
            if !handleShowingUpdate {
                scheduledVersion = version
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
        onMain {
            scheduledVersion = nil
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        onMain {
            scheduledVersion = nil
        }
    }

    // Sparkle calls its user driver delegate on the main thread.
    private nonisolated func onMain(_ body: @MainActor () -> Void) {
        MainActor.assumeIsolated(body)
    }
}
