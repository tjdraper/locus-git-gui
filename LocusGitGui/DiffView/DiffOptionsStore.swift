import Foundation

/// One repository's diff options, shared by every diff shown from it: the detail column, commit
/// windows and file windows. Changing them in one reads every one of them again, and so does
/// changing a default in Settings that the repository follows.
final class DiffOptionsStore {
    private(set) var choices: DiffOptionChoices
    private(set) var options: DiffOptions
    private var defaults: DiffOptions
    /// Called after the repository's own choices change, such as to save them with its view state.
    var onChange: ((DiffOptionChoices) -> Void)?
    private var observers: [ObjectIdentifier: (weak: Weak, handler: (DiffOptions) -> Void)] = [:]

    private struct Weak {
        weak var object: AnyObject?
    }

    init(choices: DiffOptionChoices, defaults: DiffOptions = DiffPreferences().defaultOptions) {
        self.choices = choices
        self.defaults = defaults
        options = choices.applied(to: defaults)
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: DiffPreferences.didChange) {
                guard let self else { return }
                useDefaults(DiffPreferences().defaultOptions)
            }
        }
    }

    func update(_ change: (inout DiffOptions) -> Void) {
        var options = options
        change(&options)
        guard options != self.options else { return }
        choices = DiffOptionChoices(options, defaults: defaults)
        onChange?(choices)
        show(options)
    }

    /// Held weakly, so an observer that goes away stops being told.
    func observe(_ observer: AnyObject, handler: @escaping (DiffOptions) -> Void) {
        observers[ObjectIdentifier(observer)] = (Weak(object: observer), handler)
    }

    private func useDefaults(_ defaults: DiffOptions) {
        guard defaults != self.defaults else { return }
        self.defaults = defaults
        let options = choices.applied(to: defaults)
        guard options != self.options else { return }
        show(options)
    }

    private func show(_ options: DiffOptions) {
        self.options = options
        observers = observers.filter { $0.value.weak.object != nil }
        for observer in observers.values {
            observer.handler(options)
        }
    }
}
