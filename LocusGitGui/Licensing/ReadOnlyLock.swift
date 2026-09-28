import AppKit

/// After the trial, without a license, the app opens repositories and shows everything in them, but
/// changes none of them and talks to no remote. Every command that would asks here first, before any
/// form or confirmation, and gets the purchase sheet in place of running. The commands stay enabled
/// in the menus and the palette, so what a license unlocks is plain to see.
enum ReadOnlyLock {
    /// Whether a change can go ahead. When it can't, the purchase sheet shows on `window`, or on the
    /// window in front when there's none.
    static func allowsChange(in window: NSWindow?, entitlements: EntitlementStore = .shared) -> Bool {
        guard !entitlements.isEntitled else { return true }
        PurchaseSheet.show(on: window ?? NSApp.keyWindow)
        return false
    }

    /// For what the app does by itself, such as fetching automatically, which stops quietly.
    static var isLocked: Bool {
        !EntitlementStore.shared.isEntitled
    }
}
