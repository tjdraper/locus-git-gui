import Foundation
import Testing

struct CollapsedFileMemoryTests {
    private func file(_ path: String, group: Int? = nil) -> DiffFile.Identity {
        DiffFile.Identity(group: group, path: path)
    }

    @Test
    func eachDiffKeepsItsOwnCollapsedFiles() {
        // Arrange
        var memory = CollapsedFileMemory()

        // Act
        memory.set([file("a")], in: .commit("abc"))
        memory.set([file("b", group: 1)], in: .workingArea)

        // Assert
        #expect(memory.files(in: .commit("abc")) == [file("a")])
        #expect(memory.files(in: .workingArea) == [file("b", group: 1)])
        #expect(memory.files(in: .commit("def")).isEmpty)
    }

    @Test
    func expandingEveryFileForgetsTheDiff() {
        // Arrange
        var memory = CollapsedFileMemory()
        memory.set([file("a")], in: .commit("abc"))

        // Act
        memory.set([], in: .commit("abc"))

        // Assert
        #expect(memory == CollapsedFileMemory())
    }

    @Test
    func onlyTheMostRecentlyChangedDiffsAreKept() {
        // Arrange
        var memory = CollapsedFileMemory()
        for index in 0 ..< CollapsedFileMemory.limit {
            memory.set([file("a")], in: .commit("\(index)"))
        }

        // Act
        memory.set([file("b")], in: .commit("0"))
        memory.set([file("a")], in: .commit("new"))

        // Assert
        #expect(memory.files(in: .commit("0")) == [file("b")])
        #expect(memory.files(in: .commit("1")).isEmpty)
        #expect(memory.files(in: .commit("new")) == [file("a")])
    }

    @Test
    func survivesSavingAndReading() throws {
        // Arrange
        var memory = CollapsedFileMemory()
        memory.set([file("a"), file("b/c.swift")], in: .commit("abc"))
        memory.set([file("d", group: 2)], in: .workingArea)

        // Act
        let read = try JSONDecoder().decode(CollapsedFileMemory.self, from: JSONEncoder().encode(memory))

        // Assert
        #expect(read == memory)
    }
}
