/// What the app failed at on its own in one repository, one failure for each thing it does by
/// itself. Each is cleared when that thing next succeeds, so a refresh that works doesn't hide a
/// fetch that still fails.
struct BackgroundFailures {
    enum Source: CaseIterable {
        case refresh
        case automaticFetch
    }

    private var failures: [Source: GitFailure] = [:]

    /// In a steady order, refresh first, rather than the order they happened in.
    var sources: [Source] {
        Source.allCases.filter { failures[$0] != nil }
    }

    var all: [GitFailure] {
        sources.compactMap { failures[$0] }
    }

    func failure(from source: Source) -> GitFailure? {
        failures[source]
    }

    mutating func set(_ failure: GitFailure, for source: Source) {
        failures[source] = failure
    }

    /// True when there was one to clear.
    @discardableResult
    mutating func clear(_ source: Source) -> Bool {
        failures.removeValue(forKey: source) != nil
    }
}
