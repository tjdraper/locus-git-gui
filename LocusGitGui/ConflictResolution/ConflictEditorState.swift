import Foundation

/// What the conflict window's right-hand side shows for the file picked in its list, and what its
/// buttons do, for the SwiftUI views above and around the panes.
@Observable
final class ConflictEditorState {
    enum Mode: Equatable {
        /// With a message, such as when every conflict is resolved.
        case empty(String)
        case reading
        /// Resolved by editing the result.
        case editing
        /// Resolved by taking one version of the file whole.
        case choosing(ConflictVersionOptions)
        case failed(String)
    }

    var mode = Mode.empty("")
    var names = ConflictSideNames(ours: "", theirs: "")
    var conflictCount = 0
    /// Counted from zero, among `conflictCount`.
    var current: Int?
    var isEdited = false
    var hasBase = false
    var showsBase = false

    @ObservationIgnored var goToConflict: ((_ offset: Int) -> Void)?
    @ObservationIgnored var take: ((ConflictMarkers.Choice) -> Void)?
    @ObservationIgnored var save: (() -> Void)?
    @ObservationIgnored var markResolved: (() -> Void)?
    @ObservationIgnored var choose: ((ConflictVersionChoice) -> Void)?
    @ObservationIgnored var showFailureDetails: (() -> Void)?

    var takeOursTitle: String {
        "Take “\(Self.shortened(names.ours))”"
    }

    var takeTheirsTitle: String {
        "Take “\(Self.shortened(names.theirs))”"
    }

    static let takeBothTitle = "Take Both"

    /// How much of a side's name a button or menu item shows. A rebase names the commit it's
    /// replaying with its subject, which can be as long as a sentence.
    private static let longestName = 36

    /// Cut from the middle, so a commit's hash and the end of its subject both stay.
    static func shortened(_ name: String) -> String {
        guard name.count > longestName else { return name }
        let half = (longestName - 1) / 2
        return "\(name.prefix(half))…\(name.suffix(half))"
    }
}

/// The versions a file with a conflict that isn't in its lines can be resolved to, and why there's
/// nothing to combine, worded with each side's name.
struct ConflictVersionOptions: Equatable {
    struct Option: Equatable {
        let choice: ConflictVersionChoice
        let title: String
        let detail: String
    }

    let explanation: String
    let options: [Option]

    init(_ contents: ConflictFileContents, names: ConflictSideNames) {
        let ours = "“\(ConflictEditorState.shortened(names.ours))”"
        let theirs = "“\(ConflictEditorState.shortened(names.theirs))”"
        let stages = contents.stages
        explanation = switch (stages.ours, stages.theirs) {
        case (.some, nil): "\(theirs) deleted this file, and \(ours) changed it."
        case (nil, .some): "\(ours) deleted this file, and \(theirs) changed it."
        case (nil, nil): "Both sides deleted this file, or moved it to different places."
        case let (.some(oursVersion), .some(theirsVersion)):
            if oursVersion.isSubmodule || theirsVersion.isSubmodule {
                "The submodule points at a different commit on each side."
            } else if oursVersion.isSymbolicLink || theirsVersion.isSymbolicLink {
                "This is a symbolic link on at least one side, so its versions can’t be combined line by line."
            } else {
                "This file isn’t UTF-8 text, so its versions can’t be combined line by line here."
            }
        }
        options = ConflictVersionChoice.choices(for: stages).map { choice in
            switch choice {
            case .ours:
                Option(choice: .ours, title: "Take \(ours)", detail: "Keeps the file as \(ours) has it.")
            case .theirs:
                Option(choice: .theirs, title: "Take \(theirs)", detail: "Keeps the file as \(theirs) has it.")
            case .delete:
                Option(choice: .delete, title: "Delete the File", detail: Self.deletionDetail(stages, ours: ours, theirs: theirs))
            }
        }
    }

    private static func deletionDetail(_ stages: ConflictStages, ours: String, theirs: String) -> String {
        switch (stages.ours, stages.theirs) {
        case (nil, .some): "Deletes it, as \(ours) did."
        case (.some, nil): "Deletes it, as \(theirs) did."
        default: "Leaves it deleted."
        }
    }
}
