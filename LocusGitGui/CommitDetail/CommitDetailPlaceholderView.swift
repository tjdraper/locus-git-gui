import SwiftUI

/// What the detail column says in place of a commit: that none is selected, or that Git couldn't
/// read the one that is.
@Observable
final class CommitDetailPlaceholder {
    enum State: Equatable {
        case hidden
        case noCommit
        case failed(summary: String)
    }

    var state = State.noCommit
    @ObservationIgnored var showDetails: (() -> Void)?
}

struct CommitDetailPlaceholderView: View {
    let model: CommitDetailPlaceholder

    var body: some View {
        switch model.state {
        case .hidden:
            EmptyView()
        case .noCommit:
            ContentUnavailableView("No Commit Selected", systemImage: "square.stack.3d.up")
        case let .failed(summary):
            ContentUnavailableView {
                Label("Changes Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(summary)
            } actions: {
                Button("Show Details") { model.showDetails?() }
            }
        }
    }
}
