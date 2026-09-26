/// One repository's collapsed files, shared by every diff shown from it that remembers them: the
/// detail column, commit windows and the working area window. A change in one shows in the others
/// showing the same diff.
final class CollapsedFilesStore {
    private(set) var memory: CollapsedFileMemory
    /// Called after a change, such as to save it with the repository's view state.
    var onChange: ((CollapsedFileMemory) -> Void)?
    private var observers: [ObjectIdentifier: (weak: Weak, handler: (CollapsedFileMemory.Diff, Set<DiffFile.Identity>) -> Void)] = [:]

    private struct Weak {
        weak var object: AnyObject?
    }

    init(memory: CollapsedFileMemory) {
        self.memory = memory
    }

    func files(in diff: CollapsedFileMemory.Diff) -> Set<DiffFile.Identity> {
        memory.files(in: diff)
    }

    func set(_ files: Set<DiffFile.Identity>, in diff: CollapsedFileMemory.Diff) {
        var memory = memory
        memory.set(files, in: diff)
        guard memory != self.memory else { return }
        self.memory = memory
        onChange?(memory)
        observers = observers.filter { $0.value.weak.object != nil }
        for observer in observers.values {
            observer.handler(diff, files)
        }
    }

    /// Held weakly, so an observer that goes away stops being told.
    func observe(_ observer: AnyObject, handler: @escaping (CollapsedFileMemory.Diff, Set<DiffFile.Identity>) -> Void) {
        observers[ObjectIdentifier(observer)] = (Weak(object: observer), handler)
    }
}
