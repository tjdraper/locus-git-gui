import AppKit
import OSLog

/// Whether the app may change repositories right now, for the lock, the toolbar's notice, the
/// dashboard and Settings to follow. The app has one trial, so there's one of these, as there's one
/// `UpdateAvailability`.
///
/// Nothing happens when a trial runs out: a date simply passes. So this wakes itself each time the
/// days left go down, and on the last day at the end itself, and the lock arrives with the app open
/// rather than at the next click.
@Observable
final class EntitlementStore {
    static let shared = EntitlementStore()

    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "Trial")
    private static let cloudKey = "TrialStart"

    private(set) var entitlement = Entitlement.checking
    private(set) var isEntitled = true
    private(set) var trialDaysLeft: Int?
    private(set) var notice: TrialNotice?
    /// When the trial started, once it's been read.
    private(set) var trialStart: Date?

    @ObservationIgnored private var override: TrialClock.Override?
    @ObservationIgnored private var records = TrialStartRecords()
    @ObservationIgnored private var nextChange: Task<Void, Never>?
    @ObservationIgnored private var watches: [NotificationWatch] = []
    private let cloud = NSUbiquitousKeyValueStore.default

    /// Reads the trial's start, or starts the trial, and keeps following it.
    func start() {
        #if DEBUG
        override = TrialClock.Override(launchArguments: ProcessInfo.processInfo.arguments, now: .now)
        if let override {
            Self.log.info("The trial clock is overridden from the launch arguments: \(String(describing: override), privacy: .public)")
        }
        #endif
        watches = [
            NotificationWatch(NSUbiquitousKeyValueStore.didChangeExternallyNotification) { [weak self] in self?.cloudDidChange() },
            // A Mac asleep across a day's end or the trial's end wakes the timer late.
            NotificationWatch(NSApplication.didBecomeActiveNotification) { [weak self] in self?.evaluate() },
        ]
        cloud.synchronize()
        Task {
            let keychain = await Task.detached { TrialStartKeychain().read() }.value
            switch keychain {
            case let .found(date): records.keychain = date
            case .notFound: break
            case let .failed(status):
                Self.log.error("Couldn’t read the trial’s start from the Keychain: \(status, privacy: .public)")
            }
            records.cloud = cloudStart()
            settle()
        }
    }

    /// The Mac that started first wins, even when this one has already started a trial of its own.
    private func cloudDidChange() {
        guard entitlement.reason != .checking else { return }
        let start = cloudStart()
        guard start != records.cloud else { return }
        records.cloud = start
        settle()
    }

    private func cloudStart() -> Date? {
        (cloud.object(forKey: Self.cloudKey) as? TimeInterval).map(Date.init(timeIntervalSinceReferenceDate:))
    }

    private func settle() {
        let now = Date.now
        let settled = records.settled(now: now)
        // An overridden clock is for trying the lock out, and shouldn't start a real trial either.
        if override == nil {
            write(settled)
        }
        trialStart = settled.start
        entitlement = .trial(startedAt: settled.start, override: override, now: now)
        evaluate()
    }

    private func write(_ settled: TrialStartRecords.Settled) {
        if settled.writesCloud {
            cloud.set(settled.start.timeIntervalSinceReferenceDate, forKey: Self.cloudKey)
            records.cloud = settled.start
        }
        if settled.writesKeychain {
            records.keychain = settled.start
            Task.detached { [start = settled.start, log = Self.log] in
                let status = TrialStartKeychain().write(start)
                if status != errSecSuccess {
                    log.error("Couldn’t keep the trial’s start in the Keychain: \(status, privacy: .public)")
                }
            }
        }
        if settled.writesCloud || settled.writesKeychain {
            Self.log.info(
                """
                Kept the trial’s start in the Keychain \(settled.writesKeychain, privacy: .public), \
                in iCloud \(settled.writesCloud, privacy: .public)
                """
            )
        }
    }

    private func evaluate() {
        let now = Date.now
        let wasEntitled = isEntitled
        isEntitled = entitlement.isEntitled(at: now)
        trialDaysLeft = entitlement.trialDaysLeft(at: now)
        notice = TrialNotice.current(for: entitlement, now: now)
        if wasEntitled, !isEntitled {
            Self.log.info("The trial has ended, and repositories are read-only")
        }
        scheduleNextChange(after: now)
    }

    private func scheduleNextChange(after now: Date) {
        nextChange?.cancel()
        guard let date = entitlement.nextChange(after: now) else {
            nextChange = nil
            return
        }
        nextChange = Task { [weak self] in
            try? await Task.sleep(for: .seconds(date.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }
}
