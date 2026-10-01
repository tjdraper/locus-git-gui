import Foundation
import os

/// Where each of a file's threads goes in the diff shown: on its lines as they are now, or at the
/// top of the file, outdated, once the lines themselves have changed.
struct ReviewThreadPlacer {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "Reviews")

    struct Placement: Equatable {
        let place: DiffInsert.Place
        /// Such as "Lines 12–14".
        let label: String
        let isOutdated: Bool
    }

    /// The file's contents on each side of the diff shown, which the threads' lines are followed to.
    struct Sides {
        let old: String?
        let new: String?
    }

    let session: ReviewSession

    func place(_ threads: [ReviewThread], in file: ChangedFile, sides: Sides) async -> [UUID: Placement] {
        var placements: [UUID: Placement] = [:]
        for thread in threads {
            switch thread.place {
            case .review:
                continue
            case let .file(path):
                guard path == file.path else { continue }
                placements[thread.id] = Placement(place: .top, label: "File", isOutdated: false)
            case let .lines(anchor):
                guard anchor.path == file.path || anchor.path == file.originalPath else { continue }
                let side: DiffInsert.Side = anchor.side == .old ? .old : .new
                let object = side == .old ? sides.old : sides.new
                if let lines = await follow(anchor, to: object) {
                    placements[thread.id] = Placement(
                        place: .line(side, lines.upperBound),
                        label: ReviewLineAnchor.label(lines),
                        isOutdated: false
                    )
                } else {
                    placements[thread.id] = Placement(place: .top, label: ReviewLineAnchor.label(anchor.lines), isOutdated: true)
                }
            }
        }
        return placements
    }

    private func follow(_ anchor: ReviewLineAnchor, to object: String?) async -> ClosedRange<Int>? {
        guard let object else { return nil }
        if object == anchor.object {
            return anchor.lines
        }
        do {
            let command = ReviewAnchorFollowing.changesCommand(from: anchor.object, to: object)
            let (result, patches) = try await session.commands.readPatch(command, limits: .oneFile)
            guard result.status == 0 else { return nil }
            return ReviewAnchorFollowing.follow(anchor.lines, through: patches.first?.hunks ?? [])
        } catch {
            Self.log.error("Following a comment's lines failed: \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }
}
