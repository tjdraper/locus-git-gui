import AppKit

/// Copies the app into `/Applications`, clears the download quarantine, and relaunches from there.
struct ApplicationsFolderMover {
    enum Failure: LocalizedError {
        case noApplicationsFolder
        case couldNotReplaceExistingApp
        case copyFailed(any Error)

        var errorDescription: String? {
            switch self {
            case .noApplicationsFolder:
                "The Applications folder could not be found."
            case .couldNotReplaceExistingApp:
                "An existing copy of Locus Git Gui in Applications could not be moved to the Trash."
            case let .copyFailed(error):
                error.localizedDescription
            }
        }
    }

    let location: AppBundleLocation

    func moveAndRelaunch() throws {
        let destination = try destinationURL()
        try trashExistingApp(at: destination)

        do {
            try FileManager.default.copyItem(at: location.originalURL, to: destination)
        } catch {
            throw Failure.copyFailed(error)
        }

        clearQuarantine(at: destination)
        trashOriginal()
        relaunch(from: destination)
    }

    private func destinationURL() throws -> URL {
        guard let applications = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first else {
            throw Failure.noApplicationsFolder
        }
        return applications.appending(path: location.originalURL.lastPathComponent)
    }

    private func trashExistingApp(at destination: URL) throws {
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        do {
            try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
        } catch {
            throw Failure.couldNotReplaceExistingApp
        }
    }

    /// A copied bundle keeps the download quarantine flag, which would make Gatekeeper run the
    /// new copy translocated too. Failing to clear it is not worth aborting the move over.
    private func clearQuarantine(at destination: URL) {
        try? (destination as NSURL).setResourceValue(nil, forKey: .quarantinePropertiesKey)
    }

    /// `NSWorkspace.recycle` finishes in the background, and the app quits before it gets there,
    /// which leaves the original behind. The copy in Applications is already in place, so a
    /// leftover original is not worth aborting the move over.
    private func trashOriginal() {
        try? FileManager.default.trashItem(at: location.originalURL, resultingItemURL: nil)
    }

    private func relaunch(from destination: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }
}
