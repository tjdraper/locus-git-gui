import AppKit
import SwiftUI

/// The search field over the list of results. Sized to its results, and it tells the panel its
/// height so the panel can grow and shrink downward from where it opened.
struct CommandPaletteView: View {
    static let width: CGFloat = 600
    private static let rowHeight: CGFloat = 30
    private static let visibleRowLimit = 10
    private static let listPadding: CGFloat = 6

    @Bindable var session: CommandPaletteSession
    let choose: (Int) -> Void
    let heightChanged: (CGFloat) -> Void

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                TextField(session.step.placeholder, text: $session.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            results
        }
        .frame(width: Self.width)
        .glassEffect(.regular, in: .rect(cornerRadius: CommandPalettePanel.cornerRadius))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heightChanged($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: session.focusRequests, initial: true) {
            // SwiftUI ignores a focus change made in the same pass the view appears in.
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
    }

    @ViewBuilder private var results: some View {
        let results = session.results
        if results.isEmpty {
            Text(session.isAtFirstStep ? "No Matching Commands" : "No Matches")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: Self.rowHeight + Self.listPadding * 2)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results.indices, id: \.self) { index in
                            CommandPaletteRow(item: results[index].item, isSelected: index == session.selectedIndex)
                                .frame(height: Self.rowHeight)
                                .id(index)
                                .contentShape(.rect)
                                .onTapGesture { choose(index) }
                        }
                    }
                    .padding(Self.listPadding)
                }
                .frame(height: CGFloat(min(results.count, Self.visibleRowLimit)) * Self.rowHeight + Self.listPadding * 2)
                .onChange(of: session.selectedIndex) {
                    proxy.scrollTo(session.selectedIndex)
                }
            }
        }
    }
}

/// The palette keeps focus in its search field while the arrows move the selection, so the row
/// draws its own highlight rather than a `List`'s, which would show as unfocused.
private struct CommandPaletteRow: View {
    let item: CommandPaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(item.title)
                .layoutPriority(1)
            Text(item.detail)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .foregroundStyle(Color(nsColor: isSelected ? .alternateSelectedControlTextColor : .labelColor))
        .background(isSelected ? Color(nsColor: .selectedContentBackgroundColor) : .clear, in: .rect(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
