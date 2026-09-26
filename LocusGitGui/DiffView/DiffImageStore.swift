import Foundation

/// The before and after images of a diff's image files, read the first time each comes into view
/// and kept while the same diff is shown, so scrolling back doesn't read them again.
final class DiffImageStore {
    /// Reads one side of an image: its contents, or nil when it's too large to read, and its size.
    /// Nil when the file isn't on that side.
    var read: ((ChangedFile, _ isNew: Bool) async throws -> (data: Data?, byteCount: Int)?)?
    var onLoad: (() -> Void)?

    private var states: [String: DiffImagesView.State] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    /// Starts reading the file's images the first time it's asked for.
    func state(of file: ChangedFile) -> DiffImagesView.State {
        if let state = states[file.path] {
            return state
        }
        load(file)
        return .loading
    }

    func removeAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks = [:]
        states = [:]
    }

    private func load(_ file: ChangedFile) {
        guard let read, tasks[file.path] == nil else { return }
        tasks[file.path] = Task { [weak self] in
            let state: DiffImagesView.State
            do {
                state = try await .loaded(
                    before: Self.side(of: file, isNew: false, read: read),
                    after: Self.side(of: file, isNew: true, read: read)
                )
            } catch {
                state = .failed
            }
            guard !Task.isCancelled, let self else { return }
            states[file.path] = state
            onLoad?()
        }
    }

    private static func side(
        of file: ChangedFile,
        isNew: Bool,
        read: (ChangedFile, Bool) async throws -> (data: Data?, byteCount: Int)?
    ) async throws -> DiffImage? {
        guard let contents = try await read(file, isNew) else { return nil }
        return await DiffImage.decode(contents.data, byteCount: contents.byteCount)
    }
}
