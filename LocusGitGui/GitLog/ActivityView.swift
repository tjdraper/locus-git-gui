import SwiftUI

/// What the app is doing in a repository and everything it did this session: the commands still
/// running, each with Cancel, above every command that finished, newest first, with failures open.
/// A command that finished before the window was opened is still here to look at.
struct ActivityView: View {
    let log: GitCommandLog

    var body: some View {
        VStack(spacing: 0) {
            if log.entries.isEmpty, log.running.isEmpty {
                ContentUnavailableView(
                    "No Activity Yet",
                    systemImage: "terminal",
                    description: Text("Every Git command Locus Git Gui runs in this repository shows up here.")
                )
            } else {
                List {
                    if !log.running.isEmpty {
                        Section("Running") {
                            ForEach(log.running.reversed()) { command in
                                RunningCommandRow(command: command)
                            }
                        }
                    }
                    if !log.entries.isEmpty {
                        Section("Finished") {
                            ForEach(log.entries) { entry in
                                FinishedCommandRow(entry: entry)
                            }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text(log.entries.count == 1 ? "1 command" : "\(log.entries.count) commands")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear", action: log.clear)
                    .disabled(log.entries.isEmpty)
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.transcript, forType: .string)
                }
                .disabled(log.entries.isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 560, minHeight: 320)
    }
}

private struct RunningCommandRow: View {
    let command: GitCommandLog.RunningCommand

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(command.commandLine)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            // Counts up while it runs, so a command that's stuck is plain to see.
            TimelineView(.periodic(from: command.startedAt, by: 1)) { context in
                Text(Duration.seconds(max(context.date.timeIntervalSince(command.startedAt), 0))
                    .formatted(.time(pattern: .minuteSecond)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button("Cancel", action: command.cancel)
                .controlSize(.small)
        }
    }
}

private struct FinishedCommandRow: View {
    let entry: GitLogEntry
    @State private var isExpanded: Bool

    init(entry: GitLogEntry) {
        self.entry = entry
        _isExpanded = State(initialValue: !entry.succeeded && !Self.wasCancelled(entry))
    }

    /// Stopped by the user or the app on purpose, which isn't a failure and isn't shown as one.
    private static func wasCancelled(_ entry: GitLogEntry) -> Bool {
        if case .cancelled = entry.outcome { true } else { false }
    }

    private var symbol: String {
        if Self.wasCancelled(entry) {
            "minus.circle"
        } else {
            entry.succeeded ? "checkmark.circle" : "xmark.octagon.fill"
        }
    }

    private var symbolColor: Color {
        if Self.wasCancelled(entry) {
            .secondary
        } else {
            entry.succeeded ? Color.green.opacity(0.6) : Color.red
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(entry.output.isEmpty ? "No output." : entry.output)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(entry.output.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(symbolColor)
                Text(entry.commandLine)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(entry.statusDescription)
                    .foregroundStyle(entry.succeeded || Self.wasCancelled(entry) ? Color.secondary : Color.red)
                Text(entry.durationDescription)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(entry.startedAt.formatted(date: .omitted, time: .standard))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
