import Foundation
import Testing

struct DiffPlaceMemoryTests {
    private func file(_ path: String, group: Int? = nil) -> DiffFile.Identity {
        DiffFile.Identity(group: group, path: path)
    }

    private func collapsing(_ files: DiffFile.Identity...) -> DiffPlace {
        DiffPlace(collapsed: Set(files))
    }

    @Test
    func eachDiffKeepsItsOwnPlace() {
        // Arrange
        var memory = DiffPlaceMemory()
        let scrolled = DiffPlace(
            picked: [file("b", group: 1)],
            marked: file("b", group: 1),
            scroll: DiffScrollAnchor(file: file("b", group: 1), position: .init(hunk: 2, line: 7), offset: 3)
        )

        // Act
        memory.set(collapsing(file("a")), in: .commit("abc"))
        memory.set(scrolled, in: .workingArea)

        // Assert
        #expect(memory.place(in: .commit("abc")) == collapsing(file("a")))
        #expect(memory.place(in: .workingArea) == scrolled)
        #expect(memory.place(in: .commit("def")) == DiffPlace())
    }

    @Test
    func aDiffLeftAsItStartsIsForgotten() {
        // Arrange
        var memory = DiffPlaceMemory()
        memory.set(collapsing(file("a")), in: .commit("abc"))

        // Act
        memory.set(DiffPlace(), in: .commit("abc"))

        // Assert
        #expect(memory == DiffPlaceMemory())
    }

    @Test
    func onlyTheMostRecentlyChangedDiffsAreKept() {
        // Arrange
        var memory = DiffPlaceMemory()
        for index in 0 ..< DiffPlaceMemory.limit {
            memory.set(collapsing(file("a")), in: .commit("\(index)"))
        }

        // Act
        memory.set(collapsing(file("b")), in: .commit("0"))
        memory.set(collapsing(file("a")), in: .commit("new"))

        // Assert
        #expect(memory.place(in: .commit("0")) == collapsing(file("b")))
        #expect(memory.place(in: .commit("1")) == DiffPlace())
        #expect(memory.place(in: .commit("new")) == collapsing(file("a")))
    }

    @Test
    func survivesSavingAndReading() throws {
        // Arrange
        var memory = DiffPlaceMemory()
        memory.set(collapsing(file("a"), file("b/c.swift")), in: .commit("abc"))
        memory.set(
            DiffPlace(scroll: DiffScrollAnchor(file: file("d", group: 2), position: .init(hunk: -1, line: 0), offset: 12.5)),
            in: .workingArea
        )

        // Act
        let read = try JSONDecoder().decode(DiffPlaceMemory.self, from: JSONEncoder().encode(memory))

        // Assert
        #expect(read == memory)
    }
}
