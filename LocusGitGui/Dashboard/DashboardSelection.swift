import Foundation

/// Which rows are selected, following a Finder list: a click selects one row, Command-click adds or
/// removes one, and Shift-click or Shift with an arrow selects everything from where the selection
/// started. Takes the rows as they're shown, by `id`, since searching changes which are.
nonisolated struct DashboardSelection: Equatable {
    private var ids: Set<String> = []
    /// Where Shift extends from.
    private var anchor: String?
    /// The row the arrow keys move from.
    private var cursor: String?

    /// With no selected row showing, the first row is selected, so the best match stays selected as
    /// the user types.
    func selected(in rows: [String]) -> [String] {
        let shown = rows.filter(ids.contains)
        return shown.isEmpty ? Array(rows.prefix(1)) : shown
    }

    mutating func click(_ id: String, in rows: [String], extending: Bool, toggling: Bool) {
        if toggling {
            var selected = Set(selected(in: rows))
            if selected.contains(id) {
                selected.remove(id)
            } else {
                selected.insert(id)
            }
            ids = selected
            anchor = id
            cursor = id
        } else if extending {
            extend(to: id, in: rows)
        } else {
            select(id)
        }
    }

    mutating func move(by offset: Int, in rows: [String], extending: Bool) {
        guard !rows.isEmpty else { return }
        let from = currentCursor(in: rows).flatMap(rows.firstIndex(of:)) ?? 0
        let target = rows[min(max(from + offset, 0), rows.count - 1)]
        if extending {
            extend(to: target, in: rows)
        } else {
            select(target)
        }
    }

    /// Selects the row that takes the place of the first of the removed rows.
    mutating func selectAfterRemoving(_ removed: Set<String>, from rows: [String]) {
        let remaining = rows.filter { !removed.contains($0) }
        guard let first = rows.firstIndex(where: removed.contains), !remaining.isEmpty else {
            self = DashboardSelection()
            return
        }
        select(remaining[min(first, remaining.count - 1)])
    }

    private mutating func select(_ id: String) {
        ids = [id]
        anchor = id
        cursor = id
    }

    private mutating func extend(to id: String, in rows: [String]) {
        let start = anchor.flatMap(rows.firstIndex(of:)) ?? currentCursor(in: rows).flatMap(rows.firstIndex(of:)) ?? 0
        guard let end = rows.firstIndex(of: id) else { return }
        ids = Set(rows[min(start, end)...max(start, end)])
        anchor = rows[start]
        cursor = id
    }

    /// The row the arrow keys move from, which is kept in view.
    func currentCursor(in rows: [String]) -> String? {
        let selected = selected(in: rows)
        if let cursor, selected.contains(cursor) {
            return cursor
        }
        return selected.first
    }
}
