import Foundation
import Testing

struct SearchPickHistoryTests {
    private let safari = "/work/safari"
    private let slack = "/work/slack"
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test
    func boostsItemsPickedForTheSameTerm() {
        // Arrange
        var history = SearchPickHistory()
        history.record(term: "saf", item: safari, at: start)

        // Act
        let boosts = history.boosts(for: "saf", at: start)

        // Assert
        #expect(boosts == [safari: 1])
    }

    @Test
    func boostsItemsPickedForLongerTermsLess() throws {
        // Arrange
        var history = SearchPickHistory()
        history.record(term: "saf", item: safari, at: start)
        history.record(term: "s", item: slack, at: start)

        // Act
        let boosts = history.boosts(for: "s", at: start)

        // Assert
        #expect(try #require(boosts[slack]) > #require(boosts[safari]))
    }

    @Test
    func ignoresTermsThatDontStartWithTheQuery() {
        // Arrange
        var history = SearchPickHistory()
        history.record(term: "saf", item: safari, at: start)

        // Act
        let boosts = history.boosts(for: "sl", at: start)

        // Assert
        #expect(boosts.isEmpty)
    }

    @Test
    func recentPicksOutweighOlderOnes() throws {
        // Arrange
        var history = SearchPickHistory()
        history.record(term: "s", item: safari, at: start)
        history.record(term: "s", item: safari, at: start)
        let later = start.addingTimeInterval(SearchPickHistory.halfLife * 2)
        history.record(term: "s", item: slack, at: later)

        // Act
        let boosts = history.boosts(for: "s", at: later)

        // Assert
        #expect(try #require(boosts[slack]) > #require(boosts[safari]))
    }

    @Test
    func forgetsPicksThatHaveFadedAway() {
        // Arrange
        var history = SearchPickHistory()
        history.record(term: "saf", item: safari, at: start)
        let later = start.addingTimeInterval(SearchPickHistory.halfLife * 5)

        // Act
        history.record(term: "sl", item: slack, at: later)

        // Assert
        #expect(history.entries.map(\.item) == [slack])
    }

    @Test
    func weighsEachItemAcrossEveryTerm() throws {
        // Arrange
        var history = SearchPickHistory()
        history.record(term: "", item: safari, at: start)
        history.record(term: "saf", item: safari, at: start)
        history.record(term: "", item: slack, at: start)

        // Act
        let weights = history.weights(at: start)

        // Assert
        #expect(try #require(weights[safari]) > #require(weights[slack]))
    }

    @Test
    func picksWithNothingTypedBoostNoTerm() {
        // Arrange
        var history = SearchPickHistory()
        history.record(term: "", item: safari, at: start)

        // Act
        let boosts = history.boosts(for: "s", at: start)

        // Assert
        #expect(boosts.isEmpty)
    }
}
