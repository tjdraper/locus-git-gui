import Foundation

/// How long updates have been waiting uninstalled. Two weeks on, Sparkle's window opens by itself,
/// which it otherwise never does: someone opening the app has come to do something else.
nonisolated struct UpdateNagClock {
    static let patience: TimeInterval = 14 * 24 * 60 * 60

    private static let sinceKey = "UpdatesWaitingSince"
    private static let versionKey = "UpdatesWaitingSinceAppVersion"

    let defaults: UserDefaults
    let appVersion: String

    init(
        defaults: UserDefaults = .standard,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    ) {
        self.defaults = defaults
        self.appVersion = appVersion
    }

    /// Kept from the first update found, since a newer one arriving doesn't mean the first was
    /// looked at. An update installed since starts the clock again.
    func noteFound(at date: Date = .now) {
        guard waitingSince == nil else { return }
        defaults.set(date, forKey: Self.sinceKey)
        defaults.set(appVersion, forKey: Self.versionKey)
    }

    func reset() {
        defaults.removeObject(forKey: Self.sinceKey)
        defaults.removeObject(forKey: Self.versionKey)
    }

    var waitingSince: Date? {
        guard defaults.string(forKey: Self.versionKey) == appVersion else { return nil }
        return defaults.object(forKey: Self.sinceKey) as? Date
    }

    func isOverdue(at now: Date = .now) -> Bool {
        waitingSince.map { now.timeIntervalSince($0) >= Self.patience } ?? false
    }
}
