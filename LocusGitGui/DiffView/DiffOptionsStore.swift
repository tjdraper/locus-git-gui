import Foundation

/// One repository's diff options, shared by every diff shown from it: the detail column, commit
/// windows and file windows. Changing them in one reads every one of them again.
final class DiffOptionsStore {
    private(set) var options: DiffOptions
    /// Called after the options change, such as to save them with the repository's view state.
    var onChange: ((DiffOptions) -> Void)?
    private var observers: [ObjectIdentifier: (weak: Weak, handler: (DiffOptions) -> Void)] = [:]

    private struct Weak {
        weak var object: AnyObject?
    }

    init(options: DiffOptions) {
        self.options = options
    }

    func update(_ change: (inout DiffOptions) -> Void) {
        var options = options
        change(&options)
        guard options != self.options else { return }
        self.options = options
        onChange?(options)
        observers = observers.filter { $0.value.weak.object != nil }
        for observer in observers.values {
            observer.handler(options)
        }
    }

    /// Held weakly, so an observer that goes away stops being told.
    func observe(_ observer: AnyObject, handler: @escaping (DiffOptions) -> Void) {
        observers[ObjectIdentifier(observer)] = (Weak(object: observer), handler)
    }
}
