/// Where one repository's diffs were left, shared by every diff shown from it that remembers them:
/// the detail column, commit windows and the working area window. Collapsing a file shows at once
/// in the others showing the same diff; the rest of a place is only read when a diff is shown.
final class DiffPlaceStore {
    private(set) var memory: DiffPlaceMemory
    /// Called after a change, such as to save it with the repository's view state.
    var onChange: ((DiffPlaceMemory) -> Void)?
    private var observers: [ObjectIdentifier: (weak: Weak, handler: (DiffPlaceMemory.Diff, Set<DiffFile.Identity>) -> Void)] = [:]

    private struct Weak {
        weak var object: AnyObject?
    }

    init(memory: DiffPlaceMemory) {
        self.memory = memory
    }

    func place(in diff: DiffPlaceMemory.Diff) -> DiffPlace {
        memory.place(in: diff)
    }

    func set(_ place: DiffPlace, in diff: DiffPlaceMemory.Diff) {
        let collapsed = memory.place(in: diff).collapsed
        var memory = memory
        memory.set(place, in: diff)
        guard memory != self.memory else { return }
        self.memory = memory
        onChange?(memory)
        guard place.collapsed != collapsed else { return }
        observers = observers.filter { $0.value.weak.object != nil }
        for observer in observers.values {
            observer.handler(diff, place.collapsed)
        }
    }

    /// Told when a diff's collapsed files change. Held weakly, so an observer that goes away stops
    /// being told.
    func observeCollapsedFiles(_ observer: AnyObject, handler: @escaping (DiffPlaceMemory.Diff, Set<DiffFile.Identity>) -> Void) {
        observers[ObjectIdentifier(observer)] = (Weak(object: observer), handler)
    }
}
