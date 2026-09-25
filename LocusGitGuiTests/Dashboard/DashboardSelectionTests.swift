import Foundation
import Testing

struct DashboardSelectionTests {
    private let rows = ["a", "b", "c", "d", "e"]

    @Test
    func theFirstRowIsSelectedWhenNothingElseIs() {
        // Arrange
        let selection = DashboardSelection()

        // Act
        let selected = selection.selected(in: rows)

        // Assert
        #expect(selected == ["a"])
    }

    @Test
    func theArrowsMoveASingleSelection() {
        // Arrange
        var selection = DashboardSelection()

        // Act
        selection.move(by: 1, in: rows, extending: false)
        selection.move(by: 1, in: rows, extending: false)
        selection.move(by: -1, in: rows, extending: false)

        // Assert
        #expect(selection.selected(in: rows) == ["b"])
    }

    @Test
    func theArrowsStopAtTheEnds() {
        // Arrange
        var selection = DashboardSelection()

        // Act
        selection.move(by: -1, in: rows, extending: false)

        // Assert
        #expect(selection.selected(in: rows) == ["a"])
    }

    @Test
    func shiftWithTheArrowsExtendsFromWhereTheSelectionStarted() {
        // Arrange
        var selection = DashboardSelection()
        selection.click("c", in: rows, extending: false, toggling: false)

        // Act
        selection.move(by: 1, in: rows, extending: true)
        selection.move(by: 1, in: rows, extending: true)
        selection.move(by: -1, in: rows, extending: true)

        // Assert
        #expect(selection.selected(in: rows) == ["c", "d"])
    }

    @Test
    func shiftClickSelectsTheRangeBetween() {
        // Arrange
        var selection = DashboardSelection()
        selection.click("d", in: rows, extending: false, toggling: false)

        // Act
        selection.click("b", in: rows, extending: true, toggling: false)

        // Assert
        #expect(selection.selected(in: rows) == ["b", "c", "d"])
    }

    @Test
    func commandClickAddsAndRemovesOneRow() {
        // Arrange
        var selection = DashboardSelection()
        selection.click("b", in: rows, extending: false, toggling: false)

        // Act
        selection.click("d", in: rows, extending: false, toggling: true)
        selection.click("e", in: rows, extending: false, toggling: true)
        selection.click("d", in: rows, extending: false, toggling: true)

        // Assert
        #expect(selection.selected(in: rows) == ["b", "e"])
    }

    @Test
    func aPlainClickSelectsOnlyThatRow() {
        // Arrange
        var selection = DashboardSelection()
        selection.click("b", in: rows, extending: false, toggling: false)
        selection.click("d", in: rows, extending: true, toggling: false)

        // Act
        selection.click("e", in: rows, extending: false, toggling: false)

        // Assert
        #expect(selection.selected(in: rows) == ["e"])
    }

    @Test
    func selectedRowsFilteredOutOfViewAreNotSelected() {
        // Arrange
        var selection = DashboardSelection()
        selection.click("b", in: rows, extending: false, toggling: false)
        selection.click("d", in: rows, extending: false, toggling: true)

        // Act
        let selected = selection.selected(in: ["c", "d", "e"])

        // Assert
        #expect(selected == ["d"])
    }

    @Test
    func removingRowsSelectsTheOneThatTakesTheirPlace() {
        // Arrange
        var selection = DashboardSelection()
        selection.click("b", in: rows, extending: false, toggling: false)
        selection.click("c", in: rows, extending: true, toggling: false)

        // Act
        selection.selectAfterRemoving(["b", "c"], from: rows)

        // Assert
        #expect(selection.selected(in: ["a", "d", "e"]) == ["d"])
    }

    @Test
    func removingTheLastRowsSelectsTheNewLastRow() {
        // Arrange
        var selection = DashboardSelection()
        selection.click("e", in: rows, extending: false, toggling: false)

        // Act
        selection.selectAfterRemoving(["e"], from: rows)

        // Assert
        #expect(selection.selected(in: ["a", "b", "c", "d"]) == ["d"])
    }
}
