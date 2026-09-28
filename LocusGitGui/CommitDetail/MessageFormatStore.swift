import AppKit

/// Whether commit messages read as Markdown, for every commit shown from one repository: the
/// detail column, commit windows and history windows. View > Show Message as Markdown toggles it.
@Observable
final class MessageFormatStore: NSObject, NSMenuItemValidation {
    private(set) var showsMarkdown: Bool
    /// Called after it changes, such as to save it with the repository's view state.
    @ObservationIgnored var onChange: (() -> Void)?

    init(showsMarkdown: Bool) {
        self.showsMarkdown = showsMarkdown
    }

    /// The repository's windows pass the toggle on to it from wherever it's chosen.
    func target(forAction action: Selector) -> Any? {
        action == #selector(toggleMessageMarkdown(_:)) ? self : nil
    }

    @objc func toggleMessageMarkdown(_: Any?) {
        showsMarkdown.toggle()
        onChange?()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.state = showsMarkdown ? .on : .off
        return true
    }
}
