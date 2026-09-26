import AppKit

/// Tab and Shift-Tab move focus from column to column: the sidebar's filter and list, the history's
/// Find field and list, and the commit's changes. The window handles Tab itself because AppKit's key
/// view loop can only focus views, and the sidebar's list takes focus through SwiftUI.
final class ColumnFocusCycle {
    struct Stop {
        /// False while it can't take focus, such as the sidebar while it's hidden.
        let isAvailable: () -> Bool
        let holds: (NSView) -> Bool
        let focus: () -> Void
    }

    private let stops: [Stop]

    init(stops: [Stop]) {
        self.stops = stops
    }

    /// A repository window's columns, left to right.
    convenience init(
        sidebar: SidebarModel,
        sidebarView: NSView,
        isSidebarShown: @escaping () -> Bool,
        history: HistoryViewController,
        detail: CommitDetailViewController
    ) {
        self.init(stops: [
            Stop(
                isAvailable: isSidebarShown,
                holds: { $0 is NSSearchField && $0.isDescendant(of: sidebarView) },
                focus: { [weak sidebar] in sidebar?.requestFilterFocus() }
            ),
            Stop(
                isAvailable: isSidebarShown,
                holds: { !($0 is NSSearchField) && $0.isDescendant(of: sidebarView) },
                focus: { [weak sidebar] in sidebar?.requestFocus() }
            ),
            Stop(
                isAvailable: { true },
                holds: { [weak history] in $0 === history?.findField },
                focus: { [weak history] in history?.focusFind() }
            ),
            Stop(
                isAvailable: { true },
                holds: { [weak history] in $0 === history?.table },
                focus: { [weak history] in history?.focusList() }
            ),
            Stop(
                isAvailable: { [weak detail] in detail?.focusableView != nil },
                holds: { [weak detail] view in detail.map { view.isDescendant(of: $0.view) } ?? false },
                focus: { [weak detail] in detail?.focusChanges() }
            ),
        ])
    }

    /// True when focus moved. From anywhere outside the columns, such as the toolbar, Tab starts
    /// at the first and Shift-Tab at the last.
    func move(from responder: NSResponder?, backward: Bool) -> Bool {
        let available = stops.filter { $0.isAvailable() }
        guard !available.isEmpty else { return false }
        let current = Self.view(for: responder).flatMap { view in available.firstIndex { $0.holds(view) } }
        let next = if let current {
            (current + (backward ? -1 : 1) + available.count) % available.count
        } else {
            backward ? available.count - 1 : 0
        }
        available[next].focus()
        return true
    }

    /// A field being edited has handed focus to its field editor, which stands in for the field.
    private static func view(for responder: NSResponder?) -> NSView? {
        if let editor = responder as? NSTextView, editor.isFieldEditor, let field = editor.delegate as? NSView {
            return field
        }
        return responder as? NSView
    }
}
