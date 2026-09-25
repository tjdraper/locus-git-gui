import Foundation

/// One alert covering every folder that couldn't be opened, so dropping ten folders never means
/// dismissing ten alerts.
nonisolated struct OpeningReport: Equatable {
    enum Problem: Equatable {
        case notRepository
        case bare
        case accessDenied
        case failed(String)
    }

    struct Folder: Equatable {
        let url: URL
        let problem: Problem

        var name: String {
            url.lastPathComponent
        }
    }

    let messageText: String
    let informativeText: String
    let offersPrivacySettings: Bool

    init?(folders: [Folder]) {
        guard let first = folders.first else {
            return nil
        }
        offersPrivacySettings = folders.contains { $0.problem == .accessDenied }
        if folders.count == 1 {
            (messageText, informativeText) = Self.describe(first)
        } else {
            messageText = "\(folders.count) folders couldn’t be opened"
            var lines = folders.map(Self.summarize)
            if offersPrivacySettings {
                lines.append("")
                lines.append("Allow access under Files & Folders in Privacy & Security settings, then open them again.")
            }
            informativeText = lines.joined(separator: "\n")
        }
    }

    private static func describe(_ folder: Folder) -> (String, String) {
        let path = (folder.url.path as NSString).abbreviatingWithTildeInPath
        switch folder.problem {
        case .notRepository:
            return ("“\(folder.name)” isn’t a Git repository", path)
        case .bare:
            return (
                "“\(folder.name)” is a bare repository",
                "A bare repository has no working files to show. Open a clone of it instead."
            )
        case .accessDenied:
            return (
                "Locus Git Gui isn’t allowed to read “\(folder.name)”",
                """
                macOS is keeping the app out of this folder. Allow access under Files & Folders in \
                Privacy & Security settings, then open it again.
                """
            )
        case let .failed(output):
            return ("Git couldn’t open “\(folder.name)”", output)
        }
    }

    private static func summarize(_ folder: Folder) -> String {
        switch folder.problem {
        case .notRepository:
            "“\(folder.name)” isn’t a Git repository."
        case .bare:
            "“\(folder.name)” is a bare repository, with no working files to show."
        case .accessDenied:
            "Locus Git Gui isn’t allowed to read “\(folder.name)”."
        case let .failed(output):
            "Git couldn’t open “\(folder.name)”: \(output)"
        }
    }
}
