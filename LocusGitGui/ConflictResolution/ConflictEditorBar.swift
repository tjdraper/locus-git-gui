import SwiftUI

/// The bar between the versions and the result: which conflict the cursor is at, the sides to take
/// for it, and saving and marking the file resolved. Each button's menu command has the shortcut.
struct ConflictEditorBar: View {
    let state: ConflictEditorState

    var body: some View {
        HStack(spacing: 8) {
            ControlGroup {
                Button(AppCommand.goToPreviousConflict.title, systemImage: "chevron.up") { state.goToConflict?(-1) }
                    .help(Self.help(.goToPreviousConflict))
                Button(AppCommand.goToNextConflict.title, systemImage: "chevron.down") { state.goToConflict?(1) }
                    .help(Self.help(.goToNextConflict))
            }
            .labelStyle(.iconOnly)
            .fixedSize()
            .disabled(state.conflictCount == 0)
            Text(position)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            takeButton(state.takeOursTitle, .takeOurs, color: ConflictColors.ours) { state.take?(.ours) }
            takeButton(state.takeTheirsTitle, .takeTheirs, color: ConflictColors.theirs) { state.take?(.theirs) }
            takeButton(ConflictEditorState.takeBothTitle, .takeBoth, color: nil) { state.take?(.oursThenTheirs) }
            Divider()
                .frame(height: 16)
            Button(AppCommand.saveConflictResolution.title) { state.save?() }
                .help(Self.help(.saveConflictResolution))
                .disabled(!state.isEdited)
            Button(AppCommand.markConflictResolved.title) { state.markResolved?() }
                .help(Self.help(.markConflictResolved))
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var position: String {
        if state.conflictCount == 0 {
            return "No conflicts left"
        }
        let count = state.conflictCount == 1 ? "1 conflict" : "\(state.conflictCount.formatted()) conflicts"
        guard let current = state.current else { return count }
        return "Conflict \((current + 1).formatted()) of \(state.conflictCount.formatted())"
    }

    /// With the side's colour beside it, to tie it to the pane above.
    private func takeButton(_ title: String, _ command: AppCommand, color: NSColor?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let color {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: color))
                        .frame(width: 7, height: 7)
                }
                Text(title)
                    .lineLimit(1)
            }
        }
        .help("\(title) (\(command.shortcut?.displayText ?? ""))")
        .disabled(state.current == nil)
    }

    private static func help(_ command: AppCommand) -> String {
        guard let shortcut = command.shortcut else { return command.title }
        return "\(command.title) (\(shortcut.displayText))"
    }
}
