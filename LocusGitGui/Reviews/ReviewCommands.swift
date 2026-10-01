import AppKit

/// New Review… and Show Reviews, from the menu bar, the palette and the toolbar's button, in a
/// repository's window or any window opened from it.
final class ReviewCommands: NSObject, NSMenuItemValidation {
    static let actions: Set<Selector> = [#selector(newReview(_:)), #selector(showReviews(_:))]

    private let newReview: (NSWindow?) -> Void
    private let showReviews: (NSWindow?, NSToolbarItem?) -> Void

    init(newReview: @escaping (NSWindow?) -> Void, showReviews: @escaping (NSWindow?, NSToolbarItem?) -> Void) {
        self.newReview = newReview
        self.showReviews = showReviews
    }

    @objc func newReview(_: Any?) {
        newReview(NSApp.keyWindow)
    }

    /// The toolbar's button shows the list under it.
    @objc func showReviews(_ sender: Any?) {
        showReviews(NSApp.keyWindow, sender as? NSToolbarItem)
    }

    func validateMenuItem(_: NSMenuItem) -> Bool {
        true
    }
}
