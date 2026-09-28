import SwiftUI

/// Everything the window has to say, the latest first, each in full with its buttons: in a panel
/// from the toolbar's status, or in a window of its own.
struct NoticesView: View {
    let status: ToolbarStatus
    /// Nil in the window, which is where it would open.
    let openWindow: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The window's title already says what this is.
            if let openWindow {
                HStack {
                    Text("Notices")
                        .font(.headline)
                    Spacer()
                    Button("Open in Window", systemImage: "macwindow", action: openWindow)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Open Notices in a window of its own")
                }
            }
            if status.entries.isEmpty {
                empty
            }
            ForEach(status.entries, id: \.self) { entry in
                card(for: entry)
            }
        }
        .padding(14)
        .frame(width: openWindow == nil ? nil : 380, alignment: .topLeading)
        .frame(maxHeight: openWindow == nil ? .infinity : nil, alignment: .top)
    }

    private var empty: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing to report.")
                if let idle = status.idleSummary(at: context.date) {
                    Text(idle)
                        .foregroundStyle(.secondary)
                        .help(status.lastFetchedDescription ?? "")
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func card(for entry: ToolbarStatus.Entry) -> some View {
        switch entry {
        case .remoteRunning:
            if let running = status.remote.running {
                runningCard(running)
            }
        case .stopped:
            if let stopped = status.operation.stopped {
                stoppedCard(stopped)
            }
        case .remoteNotice:
            if let notice = status.remote.notice {
                noticeCard(notice.message, hash: notice.hash, dismiss: status.remote.dismissNotice)
            }
        case .operationNotice:
            if let notice = status.operation.notice {
                noticeCard(notice.message, hash: notice.hash, dismiss: status.operation.dismissNotice)
            }
        case .update:
            NoticeCard {
                Text(status.updateMessage ?? "")
            } buttons: {
                UpdateButton(updates: status.updates)
            }
        }
    }

    private func runningCard(_ running: RemoteProgress.Running) -> some View {
        NoticeCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(running.title)
                    Spacer(minLength: 4)
                    if let progress = running.progress {
                        Text(progress.summary)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                RemoteProgressLine(progress: running.progress)
            }
        } buttons: {
            Button("Stop", action: running.cancel)
                .buttonStyle(.glass)
        }
    }

    private func stoppedCard(_ stopped: StoppedOperation) -> some View {
        NoticeCard {
            VStack(alignment: .leading, spacing: 2) {
                Text(stopped.title)
                    .fontWeight(.semibold)
                Text(stopped.detail)
                    .foregroundStyle(.secondary)
            }
        } buttons: {
            StoppedOperationButtons(status: status.operation, kind: stopped.kind)
        }
    }

    private func noticeCard(_ message: String, hash: String, dismiss: @escaping () -> Void) -> some View {
        NoticeCard {
            Text(message)
        } buttons: {
            NoticeButtons(hash: hash, dismiss: dismiss)
        }
    }
}

/// One notice: its text wrapped to as many lines as it needs, and its buttons below.
private struct NoticeCard<Content: View, Buttons: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Spacer()
                buttons
            }
            .controlSize(.small)
        }
        .font(.callout)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
    }
}
