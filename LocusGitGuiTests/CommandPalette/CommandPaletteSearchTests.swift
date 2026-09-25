import Foundation
import Testing

struct CommandPaletteSearchTests {
    private let now = Date(timeIntervalSinceReferenceDate: 0)

    private func item(_ title: String, isListedBeforeTyping: Bool = true) -> CommandPaletteItem {
        CommandPaletteItem(id: title, title: title, detail: "", shortcut: nil, isListedBeforeTyping: isListedBeforeTyping)
    }

    private func titles(_ query: String, in items: [CommandPaletteItem], history: SearchPickHistory = SearchPickHistory()) -> [String] {
        CommandPaletteSearch(items: items).rank(query, history: history, at: now).map { items[$0].title }
    }

    @Test
    func listsCommandsInMenuOrderBeforeAnythingIsTyped() {
        // Arrange
        let items = [item("New Tab"), item("Open…"), item("main", isListedBeforeTyping: false)]

        // Act
        let titles = titles("", in: items)

        // Assert
        #expect(titles == ["New Tab", "Open…"])
    }

    @Test
    func listsRecentlyUsedCommandsFirst() {
        // Arrange
        let items = [item("New Tab"), item("Open…"), item("Close")]
        var history = SearchPickHistory()
        history.record(term: "", item: "Close", at: now)

        // Act
        let titles = titles("", in: items, history: history)

        // Assert
        #expect(titles == ["Close", "New Tab", "Open…"])
    }

    @Test
    func aSearchFindsJumpsToo() {
        // Arrange
        let items = [item("Show Sidebar"), item("main", isListedBeforeTyping: false)]

        // Act
        let titles = titles("main", in: items)

        // Assert
        #expect(titles == ["main"])
    }

    @Test
    func leavesOutWhatDoesntHaveTheLettersInOrder() {
        // Arrange
        let items = [item("Remove All Missing Repositories"), item("Show Git Log")]

        // Act
        let titles = titles("sgl", in: items)

        // Assert
        #expect(titles == ["Show Git Log"])
    }

    @Test
    func aCommandPickedForASearchComesFirstForIt() {
        // Arrange
        let items = [item("Show Sidebar"), item("Show Toolbar")]
        var history = SearchPickHistory()
        history.record(term: "show", item: "Show Toolbar", at: now)

        // Act
        let titles = titles("show", in: items, history: history)

        // Assert
        #expect(titles == ["Show Toolbar", "Show Sidebar"])
    }
}
