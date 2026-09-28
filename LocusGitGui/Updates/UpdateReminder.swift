import Sparkle

/// Keeps an update found by a scheduled check from interrupting: unless the check ran just after
/// launch, the update waits behind a quiet sign until the user asks to see it.
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
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state _: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        onMain {
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
