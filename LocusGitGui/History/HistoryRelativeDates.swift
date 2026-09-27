import AppKit

/// Keeps the dates in the history's rows true while the window stays open, since “1 second ago”
/// is only right when it's written. The rows on screen are written again more often while one of
/// them is young, and the wait is on the continuous clock, which runs while the Mac sleeps, so they
/// catch up as soon as it wakes.
final class HistoryRelativeDates {
    private weak var table: NSTableView?
    private var updating: Task<Void, Never>?

    init(table: NSTableView) {
        self.table = table
    }

    /// When the rows change, since a new commit's “1 second ago” needs the shortest wait. It keeps
    /// going for as long as the history does.
    func start() {
        updating?.cancel()
        updating = Task { [weak self] in
            while !Task.isCancelled {
                guard let wait = self?.update() else { return }
                try? await Task.sleep(for: wait)
            }
        }
    }

    /// How long until the youngest row's date reads differently, give or take.
    private func update() -> Duration {
        let now = Date.now
        let youngest = visibleRows.map { $0.updateDate(now: now) }.min() ?? .infinity
        switch youngest {
        case ..<60: return .seconds(1)
        case ..<3600: return .seconds(30)
        default: return .seconds(300)
        }
    }

    private var visibleRows: [HistoryRowView] {
        guard let table else { return [] }
        let visible = table.rows(in: table.visibleRect)
        return (visible.location ..< NSMaxRange(visible)).compactMap { row in
            table.view(atColumn: 0, row: row, makeIfNecessary: false) as? HistoryRowView
        }
    }
}
