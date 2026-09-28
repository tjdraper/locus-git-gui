import Foundation

/// The update Sparkle has found and holds until the user asks to see it, for the dashboard and the
/// repository windows to offer. The app has one updater, so there's one of these, rather than one
/// handed down through every window.
@Observable
final class UpdateAvailability {
    static let shared = UpdateAvailability()

    /// The newest version found, until it's installed or skipped.
    private(set) var version: String?
    /// How many releases newer than this one this Mac can install.
    private(set) var count = 0
    private(set) var found: Date?
    /// Opens Sparkle's window for the update.
    @ObservationIgnored var show: (() -> Void)?

    var isAvailable: Bool {
        version != nil
    }

    var buttonTitle: String {
        count > 1 ? "\(count) Updates Available…" : "1 Update Available…"
    }

    func showFound(_ version: String) {
        guard self.version != version else { return }
        self.version = version
        found = .now
        count = max(count, 1)
    }

    func showCount(_ count: Int) {
        self.count = count
    }

    func clear() {
        version = nil
        found = nil
        count = 0
    }
}
