import SwiftUI

/// The repository's Git log: every command the app ran, newest first, with failures open.
struct GitLogView: View {
    let log: GitCommandLog

    var body: some View {
        VStack(spacing: 0) {
            if log.entries.isEmpty {
                ContentUnavailableView(
                    "No Commands Yet",
                    systemImage: "terminal",
                    description: Text("Every Git command Locus Git Gui runs in this repository shows up here.")
                )
            } else {
                List(log.entries) { entry in
                    GitLogRow(entry: entry)
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

private struct GitLogRow: View {
    let entry: GitLogEntry
    @State private var isExpanded: Bool

    init(entry: GitLogEntry) {
        self.entry = entry
        _isExpanded = State(initialValue: !entry.succeeded)
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
                Image(systemName: entry.succeeded ? "checkmark.circle" : "xmark.octagon.fill")
                    .foregroundStyle(entry.succeeded ? Color.green.opacity(0.6) : Color.red)
                Text(entry.commandLine)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(entry.statusDescription)
                    .foregroundStyle(entry.succeeded ? Color.secondary : Color.red)
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
