import Foundation
import Testing

struct DashboardOpenHistoryTests {
    private let safari = "/work/safari"
    private let slack = "/work/slack"
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test
    func boostsRepositoriesPickedForTheSameTerm() {
        // Arrange
        var history = DashboardOpenHistory()
        history.record(term: "saf", repository: safari, at: start)

        // Act
        let boosts = history.boosts(for: "saf", at: start)

        // Assert
        #expect(boosts == [safari: 1])
    }

    @Test
    func boostsRepositoriesPickedForLongerTermsLess() throws {
        // Arrange
        var history = DashboardOpenHistory()
        history.record(term: "saf", repository: safari, at: start)
        history.record(term: "s", repository: slack, at: start)

        // Act
        let boosts = history.boosts(for: "s", at: start)

        // Assert
        #expect(try #require(boosts[slack]) > #require(boosts[safari]))
    }

    @Test
    func ignoresTermsThatDontStartWithTheQuery() {
        // Arrange
        var history = DashboardOpenHistory()
        history.record(term: "saf", repository: safari, at: start)

        // Act
        let boosts = history.boosts(for: "sl", at: start)

        // Assert
        #expect(boosts.isEmpty)
    }

    @Test
    func recentPicksOutweighOlderOnes() throws {
        // Arrange
        var history = DashboardOpenHistory()
        history.record(term: "s", repository: safari, at: start)
        history.record(term: "s", repository: safari, at: start)
        let later = start.addingTimeInterval(DashboardOpenHistory.halfLife * 2)
        history.record(term: "s", repository: slack, at: later)

        // Act
        let boosts = history.boosts(for: "s", at: later)

        // Assert
        #expect(try #require(boosts[slack]) > #require(boosts[safari]))
    }

    @Test
    func forgetsPicksThatHaveFadedAway() {
        // Arrange
        var history = DashboardOpenHistory()
        history.record(term: "saf", repository: safari, at: start)
        let later = start.addingTimeInterval(DashboardOpenHistory.halfLife * 5)

        // Act
        history.record(term: "sl", repository: slack, at: later)

        // Assert
        #expect(history.entries.map(\.repository) == [slack])
    }
}
