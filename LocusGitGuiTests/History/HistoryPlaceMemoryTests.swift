import Foundation
import Testing

struct HistoryPlaceMemoryTests {
    @Test
    func eachSidebarItemKeepsItsOwnPlace() {
        // Arrange
        var memory = HistoryPlaceMemory()
        let checkedOut = HistoryPlace(selection: .workingArea, topCommit: nil)
        let branch = HistoryPlace(selection: .commit("abc"), topCommit: "def")

        // Act
        memory.set(checkedOut, for: nil)
        memory.set(branch, for: .ref("refs/heads/feature"))

        // Assert
        #expect(memory.place(for: nil) == checkedOut)
        #expect(memory.place(for: .ref("refs/heads/feature")) == branch)
        #expect(memory.place(for: .ref("refs/tags/v1")) == nil)
    }

    @Test
    func onlyTheMostRecentlyLeftAreKept() {
        // Arrange
        var memory = HistoryPlaceMemory()
        for index in 0 ..< HistoryPlaceMemory.limit {
            memory.set(HistoryPlace(), for: .ref("refs/heads/\(index)"))
        }

        // Act
        memory.set(HistoryPlace(selection: .commit("abc")), for: .ref("refs/heads/0"))
        memory.set(HistoryPlace(), for: nil)

        // Assert
        #expect(memory.place(for: .ref("refs/heads/0")) == HistoryPlace(selection: .commit("abc")))
        #expect(memory.place(for: .ref("refs/heads/1")) == nil)
        #expect(memory.place(for: nil) == HistoryPlace())
    }

    @Test
    func survivesSavingAndReading() throws {
        // Arrange
        var memory = HistoryPlaceMemory()
        memory.set(HistoryPlace(selection: .workingArea), for: nil)
        memory.set(HistoryPlace(selection: .commit("abc"), topCommit: "def"), for: .stash("123"))

        // Act
        let read = try JSONDecoder().decode(HistoryPlaceMemory.self, from: JSONEncoder().encode(memory))

        // Assert
        #expect(read == memory)
    }
}
