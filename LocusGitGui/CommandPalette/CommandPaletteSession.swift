import Foundation

/// One opening of the palette: the steps taken so far, what's typed, and which result is selected.
@Observable
final class CommandPaletteSession {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            updateResults()
        }
    }

    private(set) var results: [CommandPaletteEntry] = []
    private(set) var selectedIndex = 0
    /// Changes each time the search field should take focus.
    private(set) var focusRequests = 0
    private var steps: [CommandPaletteStep]
    /// What was typed at each earlier step, put back on going back to it.
    private var earlierQueries: [String] = []

    @ObservationIgnored private let history: SearchPickHistory

    init(step: CommandPaletteStep, history: SearchPickHistory) {
        steps = [step]
        self.history = history
        updateResults()
    }

    var step: CommandPaletteStep {
        steps[steps.count - 1]
    }

    var isAtFirstStep: Bool {
        steps.count == 1
    }

    var selectedEntry: CommandPaletteEntry? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func push(_ step: CommandPaletteStep) {
        earlierQueries.append(query)
        steps.append(step)
        query = ""
        updateResults()
        focusSearch()
    }

    /// False at the first step, which has nothing to go back to.
    func goBack() -> Bool {
        guard !isAtFirstStep else { return false }
        steps.removeLast()
        query = earlierQueries.removeLast()
        updateResults()
        focusSearch()
        return true
    }

    func returnToFirstStep() {
        guard !isAtFirstStep else { return }
        steps = [steps[0]]
        query = earlierQueries[0]
        earlierQueries = []
        updateResults()
        focusSearch()
    }

    func focusSearch() {
        focusRequests += 1
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), results.count - 1)
    }

    func select(_ index: Int) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
    }

    private func updateResults() {
        let step = step
        results = step.search.rank(query, history: history, at: .now).map { step.entries[$0] }
        selectedIndex = 0
    }
}
