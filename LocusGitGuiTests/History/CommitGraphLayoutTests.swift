import Testing

struct CommitGraphLayoutTests {
    private typealias Line = CommitGraphLine

    @Test
    func aStraightHistoryStaysInOneLane() {
        // Arrange
        var layout = CommitGraphLayout()

        // Act
        let rows = [
            layout.add("c", parents: ["b"]),
            layout.add("b", parents: ["a"]),
            layout.add("a", parents: []),
        ]

        // Assert
        #expect(rows.map(\.lane) == [0, 0, 0])
        #expect(rows[0].lines == [Line(fromLane: 0, toLane: 0, span: .outgoing, color: 0)])
        #expect(rows[1].lines == [
            Line(fromLane: 0, toLane: 0, span: .incoming, color: 0),
            Line(fromLane: 0, toLane: 0, span: .outgoing, color: 0),
        ])
        #expect(rows[2].lines == [Line(fromLane: 0, toLane: 0, span: .incoming, color: 0)])
    }

    @Test
    func aMergeOpensALaneForItsSecondParentThatJoinsBackAtTheirCommonParent() {
        // Arrange
        var layout = CommitGraphLayout()

        // Act
        let merge = layout.add("merge", parents: ["main", "feature"])
        let main = layout.add("main", parents: ["base"])
        let feature = layout.add("feature", parents: ["base"])
        let base = layout.add("base", parents: [])

        // Assert
        #expect(merge.lines == [
            Line(fromLane: 0, toLane: 0, span: .outgoing, color: 0),
            Line(fromLane: 0, toLane: 1, span: .outgoing, color: 1),
        ])
        #expect(main.lane == 0)
        #expect(main.lines.contains(Line(fromLane: 1, toLane: 1, span: .passing, color: 1)))
        #expect(feature.lane == 1)
        #expect(feature.lines == [
            Line(fromLane: 0, toLane: 0, span: .passing, color: 0),
            Line(fromLane: 1, toLane: 1, span: .incoming, color: 1),
            Line(fromLane: 1, toLane: 0, span: .outgoing, color: 1),
        ])
        #expect(base.lines == [Line(fromLane: 0, toLane: 0, span: .incoming, color: 0)])
        #expect([merge, main, feature, base].map(\.width) == [2, 2, 2, 1])
    }

    @Test
    func twoChildrenOfOneCommitMeetAtIt() {
        // Arrange
        var layout = CommitGraphLayout()
        _ = layout.add("left", parents: ["base"])
        // Starts to the right of `left`, whose lane already waits for `base`.
        _ = layout.add("right", parents: ["other"])
        _ = layout.add("other", parents: ["base"])

        // Act
        let base = layout.add("base", parents: [])

        // Assert
        #expect(base.lane == 0)
        #expect(base.lines == [Line(fromLane: 0, toLane: 0, span: .incoming, color: 0)])
    }

    @Test
    func unrelatedHistoriesReuseTheLaneTheLastOneLeft() {
        // Arrange
        var layout = CommitGraphLayout()
        _ = layout.add("first", parents: [])

        // Act
        let second = layout.add("second", parents: [])

        // Assert
        #expect(second.lane == 0)
        #expect(second.color == 1)
        #expect(second.lines.isEmpty)
    }

    @Test
    func aParentAnotherLaneAlreadyWaitsForIsJoinedRatherThanOpenedAgain() {
        // Arrange
        var layout = CommitGraphLayout()
        _ = layout.add("main", parents: ["base"])

        // Act
        let tip = layout.add("tip", parents: ["base"])

        // Assert
        #expect(tip.lane == 1)
        #expect(tip.lines.last == Line(fromLane: 1, toLane: 0, span: .outgoing, color: 1))
        #expect(layout.add("base", parents: []).width == 1)
    }
}
