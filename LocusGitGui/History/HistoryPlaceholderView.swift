import SwiftUI

/// What the history column says in place of commits: that it's reading, that there are none, or
/// that Git couldn't read them.
@Observable
final class HistoryPlaceholder {
    enum State: Equatable {
        case hidden
        case loading
        case noCommits
        case noMatches(String)
        case failed(summary: String)
    }

    var state = State.hidden
    @ObservationIgnored var showDetails: (() -> Void)?

    /// Nothing once there are commits to show. Before the first read, the column is loading.
    func show(_ list: HistoryList) {
        state = if let failure = list.failure {
            .failed(summary: failure.summary)
        } else if !list.commits.isEmpty {
            .hidden
        } else if list.isLoading || list.scope == nil {
            .loading
        } else if let search = list.search {
            .noMatches(search.text)
        } else {
            .noCommits
        }
    }
}

struct HistoryPlaceholderView: View {
    let model: HistoryPlaceholder

    var body: some View {
        switch model.state {
        case .hidden:
            EmptyView()
        case .loading:
            DelayedProgressView()
        case .noCommits:
            ContentUnavailableView("No Commits", systemImage: "clock")
        case let .noMatches(text):
            ContentUnavailableView.search(text: text)
        case let .failed(summary):
            ContentUnavailableView {
                Label("History Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(summary)
            } actions: {
                Button("Show Details") { model.showDetails?() }
            }
        }
    }
}

/// Only for a read that takes a moment, so a quick one doesn't flash a spinner.
private struct DelayedProgressView: View {
    @State private var isShown = false

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .opacity(isShown ? 1 : 0)
            .task {
                try? await Task.sleep(for: .milliseconds(400))
                isShown = true
            }
    }
}
