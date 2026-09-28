import AppKit
import SwiftUI

/// The status in the repository window's toolbar, on one line: the latest of a fetch, pull or push
/// with its progress, an operation stopped partway with Continue, Skip and Abort, or a notice with the
/// commit that brings back what was taken away, and otherwise when the repository last fetched. A
/// count says there's more, and a click anywhere but its buttons opens the Notices panel. It starts
/// with an icon for what it shows, which is a spinner while Git works, in a place of its own so the
/// text doesn't move each time Git starts and stops. Too narrow for its text, it's only the icon
/// (`ToolbarStatusItem` decides).
struct ToolbarStatusView: View {
    let status: ToolbarStatus
    let activity: GitActivity
    let isCompact: Bool
    let openPanel: () -> Void
    let showActivity: () -> Void

    var body: some View {
        Group {
            if isCompact {
                compact
            } else {
                full
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.callout)
        .controlSize(.small)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Below this, the status's buttons leave too few words of its text to be worth showing, such as
    /// a notice without the commit Copy Hash copies.
    static func fullWidth(for entry: ToolbarStatus.Entry?) -> CGFloat {
        switch entry {
        case .stopped, .remoteNotice, .operationNotice: 300
        case .remoteRunning: 200
        case nil: 150
        }
    }

    private var full: some View {
        HStack(spacing: 8) {
            icon
            switch status.latest {
            case .remoteRunning:
                if let running = status.remote.running {
                    remoteRunning(running)
                }
            case .stopped:
                if let stopped = status.operation.stopped {
                    stoppedOperation(stopped)
                }
            case .remoteNotice:
                if let notice = status.remote.notice {
                    self.notice(notice.message, hash: notice.hash, dismiss: status.remote.dismissNotice)
                }
            case .operationNotice:
                if let notice = status.operation.notice {
                    self.notice(notice.message, hash: notice.hash, dismiss: status.operation.dismissNotice)
                }
            case nil:
                idle
            }
            moreBadge
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .contentShape(.rect)
        .onTapGesture(perform: openPanel)
    }

    private var compact: some View {
        HStack(spacing: 4) {
            icon
            moreBadge
        }
        .padding(.horizontal, 8)
        .contentShape(.rect)
        .onTapGesture(perform: openPanel)
        .help(status.latest.flatMap(status.summary(of:)) ?? status.idleSummary(at: .now) ?? "")
    }

    /// A spinner while Git works, and the latest notice's kind when it doesn't. The icon alone shows
    /// how far a fetch, pull or push has got, which the text shows as a line beneath it otherwise.
    private var icon: some View {
        Group {
            if isCompact, let fraction = status.remote.running?.progress?.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
            } else if activity.isWorking {
                ProgressView()
                    .contentShape(.rect)
                    .onTapGesture(perform: showActivity)
                    .help("Git is working in this repository. Click to see what it’s doing.")
                    .accessibilityLabel("Git is working")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Show Activity", showActivity)
            } else {
                kindIcon
            }
        }
        .controlSize(.small)
        .frame(width: 16, height: 16)
    }

    @ViewBuilder
    private var kindIcon: some View {
        switch status.latest {
        case .remoteRunning:
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .accessibilityLabel("Talking to a remote")
        case .stopped:
            Image(systemName: "pause.circle")
                .accessibilityLabel("Operation stopped partway")
        case .remoteNotice, .operationNotice:
            Image(systemName: "arrow.uturn.backward.circle")
                .accessibilityLabel("Notice")
        case nil:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .accessibilityLabel(status.idleSummary(at: .now) ?? "Status")
        }
    }

    @ViewBuilder
    private var moreBadge: some View {
        let more = status.entries.count - 1
        if more > 0 {
            Text("+\(more)")
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: .capsule)
                .help(more == 1 ? "1 more. Click to see it." : "\(more) more. Click to see them.")
                .accessibilityLabel(more == 1 ? "1 more notice" : "\(more) more notices")
        }
    }

    private var idle: some View {
        TimelineView(.everyMinute) { context in
            Text(status.idleSummary(at: context.date) ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(status.lastFetchedDescription ?? "")
        }
    }

    private func remoteRunning(_ running: RemoteProgress.Running) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(running.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if let progress = running.progress {
                        Text(progress.summary)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                RemoteProgressLine(progress: running.progress)
            }
            .help([running.title, running.progress?.summary].compactMap(\.self).joined(separator: " · "))
            RemoteStopButton(running: running)
        }
    }

    private func stoppedOperation(_ stopped: StoppedOperation) -> some View {
        Group {
            HStack(spacing: 4) {
                Text(stopped.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                WholeWordsText(text: "· \(stopped.detail)")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("\(stopped.title). \(stopped.detail)")
            StoppedOperationButtons(status: status.operation, kind: stopped.kind)
        }
    }

    private func notice(_ message: String, hash: String, dismiss: @escaping () -> Void) -> some View {
        Group {
            WholeWordsText(text: message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(message)
            NoticeButtons(hash: hash, dismiss: dismiss)
        }
    }
}

/// How far a fetch, pull or push has got, as a thin bar, moving back and forth while Git hasn't said.
struct RemoteProgressLine: View {
    let progress: GitProgress?

    var body: some View {
        Group {
            if let fraction = progress?.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
        }
        .controlSize(.mini)
    }
}

struct RemoteStopButton: View {
    let running: RemoteProgress.Running

    var body: some View {
        Button("Stop", systemImage: "xmark.circle.fill", action: running.cancel)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Stop \(running.title.lowercasedFirstWord)")
    }
}

/// SwiftUI drops a button's bezel in a toolbar, and drew a prominent one white on white, so these
/// use the glass styles, which it keeps.
struct StoppedOperationButtons: View {
    let status: OperationStatus
    let kind: HistoryOperationCommand.Stopped

    var body: some View {
        Button("Abort…") { status.abort?() }
            .buttonStyle(.glass)
        if kind != .merge {
            Button("Skip") { status.skip?() }
                .buttonStyle(.glass)
        }
        Button("Continue") { status.continueOperation?() }
            .buttonStyle(.glassProminent)
    }
}

struct NoticeButtons: View {
    let hash: String
    let dismiss: () -> Void

    var body: some View {
        Button("Copy Hash") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hash, forType: .string)
        }
        .buttonStyle(.glass)
        Button("Dismiss", systemImage: "xmark.circle.fill", action: dismiss)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
    }
}

extension String {
    /// “Pushing “main” to “origin”” as “pushing “main” to “origin””, to follow “Stop”.
    fileprivate var lowercasedFirstWord: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
