import CoreServices
import Foundation

/// Reports that something changed under the working tree or in the Git directory, whether the app,
/// Terminal, an editor or a build changed it.
final class RepositoryFileWatcher {
    /// FSEvents gathers changes over this long into one callback. `RefreshScheduler` waits for a
    /// longer quiet spell on top.
    private static let latency: CFTimeInterval = 0.25

    private let paths: [String]
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?

    init(repository: Repository, onChange: @escaping () -> Void) {
        let workTree = repository.workTree.path
        let gitDirectory = repository.gitDirectory.path
        // A linked worktree's Git directory is outside the working tree and needs watching itself.
        paths = gitDirectory.hasPrefix(workTree) ? [workTree] : [workTree, gitDirectory]
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }
        // Unretained, because `stop()` runs before this object goes away and ends the callbacks.
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let address = UInt(bitPattern: info)
            // The stream delivers on the main queue, set below.
            MainActor.assumeIsolated {
                guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
                Unmanaged<RepositoryFileWatcher>.fromOpaque(pointer).takeUnretainedValue().onChange()
            }
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
        ) else {
            return
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
