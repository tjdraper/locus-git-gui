import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The search field keeps focus while the arrows move the selection, so the row draws its own
/// highlight rather than a `List`'s, which would show as unfocused.
struct DashboardRowView: View {
    private static let folderIcon = NSWorkspace.shared.icon(for: .folder)

    let row: DashboardRow
    /// Nil until the repository's first check finishes.
    let state: RecentRepositoryState?
    let isSelected: Bool

    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: Self.folderIcon)
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.headline)
                Text((row.repository.workTree.path as NSString).abbreviatingWithTildeInPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .truncationMode(.head)
            }
            .lineLimit(1)
            Spacer(minLength: 12)
            stateLabel
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .opacity(isUnavailable && !isSelected ? 0.6 : 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .foregroundStyle(textColor)
        .background(highlight, in: .rect(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch state {
        case let .onBranch(name):
            Label(name, systemImage: "arrow.triangle.branch")
        case let .detached(commit):
            Label("Detached HEAD at \(commit)", systemImage: "arrow.triangle.branch")
        case .missing:
            Label("Missing", systemImage: "questionmark.folder")
        case .driveNotConnected:
            Label("Drive Not Connected", systemImage: "externaldrive.badge.xmark")
        case .accessDenied:
            Label("No Access", systemImage: "lock")
                .help("""
                macOS is keeping Locus Git Gui out of this folder. Allow access under Files & Folders in \
                Privacy & Security settings.
                """)
        case let .failed(output):
            Label("Unavailable", systemImage: "exclamationmark.triangle")
                .help(output)
        case nil:
            EmptyView()
        }
    }

    private var isUnavailable: Bool {
        state == .missing || state == .driveNotConnected
    }

    private var textColor: Color {
        isSelected && appearsActive ? Color(nsColor: .alternateSelectedControlTextColor) : Color(nsColor: .labelColor)
    }

    private var highlight: Color {
        guard isSelected else {
            return .clear
        }
        return Color(nsColor: appearsActive ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor)
    }
}
