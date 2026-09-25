import Foundation

/// Where this app bundle really lives, and whether that is somewhere updates can work.
///
/// Gatekeeper runs a quarantined app from a read-only randomized copy ("app translocation"),
/// so `Bundle.main.bundleURL` is not always the path the user sees in Finder.
struct AppBundleLocation {
    /// The path the current process was launched from, which may be the translocated copy.
    let runningURL: URL

    /// The path the user sees in Finder, which is where a move has to start from.
    let originalURL: URL

    var isTranslocated: Bool {
        runningURL != originalURL
    }

    var isInApplicationsFolder: Bool {
        let applicationsPaths = FileManager.default.urls(for: .applicationDirectory, in: .allDomainsMask)
            .map(\.standardizedFileURL.path)
        let parent = originalURL.standardizedFileURL.deletingLastPathComponent().path
        return applicationsPaths.contains(parent)
    }

    static func current() -> AppBundleLocation {
        let running = Bundle.main.bundleURL.standardizedFileURL
        return AppBundleLocation(
            runningURL: running,
            originalURL: untranslocatedURL(for: running) ?? running
        )
    }

    /// `SecTranslocateCreateOriginalPathForURL` is exported by Security.framework but has no
    /// declaration in the macOS SDK headers, so it has to be resolved at runtime.
    private static func untranslocatedURL(for url: URL) -> URL? {
        typealias OriginalPathForURL = @convention(c) (
            CFURL,
            UnsafeMutablePointer<Unmanaged<CFError>?>?
        ) -> Unmanaged<CFURL>?

        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(rtldDefault, "SecTranslocateCreateOriginalPathForURL") else {
            return nil
        }
        let originalPathForURL = unsafeBitCast(symbol, to: OriginalPathForURL.self)
        guard let original = originalPathForURL(url as CFURL, nil) else {
            return nil
        }
        return (original.takeRetainedValue() as URL).standardizedFileURL
    }
}
