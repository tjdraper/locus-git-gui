import Foundation

/// The `git` the user picked. It is kept as a path and used until they pick another, so a new Git
/// appearing on the PATH never changes which one the app runs.
nonisolated struct GitChoice {
    enum Availability: Equatable, Sendable {
        case notChosen
        case missing(URL)
        case available(URL)
    }

    private static let defaultsKey = "GitExecutablePath"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var executableURL: URL? {
        get { defaults.string(forKey: Self.defaultsKey).map { URL(filePath: $0) } }
        nonmutating set { defaults.set(newValue?.path, forKey: Self.defaultsKey) }
    }

    func availability(isUsable: (URL) async -> Bool) async -> Availability {
        guard let executableURL else {
            return .notChosen
        }
        return await isUsable(executableURL) ? .available(executableURL) : .missing(executableURL)
    }
}
