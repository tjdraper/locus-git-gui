import AppKit
import SwiftUI

struct DashboardView: View {
    struct Actions {
        let open: ([DashboardRow]) -> Void
        let remove: ([DashboardRow]) -> Void
        let removeAllMissing: () -> Void
        let setDisplayName: (DashboardRow) -> Void
        let showInFinder: (DashboardRow) -> Void
        let showOpenPanel: () -> Void
        let rowAppeared: (DashboardRow) -> Void
        let rowDisappeared: (DashboardRow) -> Void
    }

    @Bindable var session: DashboardSession
    let actions: Actions

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField("Search Repositories", text: $session.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            list
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
        .onChange(of: session.searchFocusRequests, initial: true) {
            // SwiftUI ignores a focus change made in the same pass the view appears in.
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
    }

    private var list: some View {
        let rows = session.rows
        let selected = session.selectedRows
        let selectedIDs = Set(selected.map(\.id))
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(rows) { row in
                        DashboardRowView(row: row, state: session.state(of: row.id), isSelected: selectedIDs.contains(row.id))
                            .id(row.id)
                            .contentShape(.rect)
                            .onTapGesture(count: 2) { actions.open(targets(of: row, selected: selected)) }
                            .simultaneousGesture(TapGesture().onEnded {
                                let modifiers = NSEvent.modifierFlags
                                session.click(row, extending: modifiers.contains(.shift), toggling: modifiers.contains(.command))
                            })
                            .contextMenu { contextMenu(for: targets(of: row, selected: selected)) }
                            .onAppear { actions.rowAppeared(row) }
                            .onDisappear { actions.rowDisappeared(row) }
                    }
                }
                .padding(8)
            }
            .onChange(of: session.cursorID) {
                if let cursorID = session.cursorID {
                    proxy.scrollTo(cursorID)
                }
            }
        }
        .overlay {
            if !session.hasRecentRepositories {
                ContentUnavailableView(
                    "No Recent Repositories",
                    systemImage: "folder",
                    description: Text("Repositories you open appear here.")
                )
            } else if rows.isEmpty {
                ContentUnavailableView.search(text: session.query)
            }
        }
    }

    private var bottomBar: some View {
        let missingCount = session.missingRepositories.count
        return HStack {
            if missingCount > 0 {
                Toggle(isOn: $session.showsOnlyMissing) {
                    Label("\(missingCount) Missing", systemImage: "exclamationmark.triangle")
                }
                .toggleStyle(.button)
                .help(DashboardCommandTitle.showOnlyMissing)
            }
            Spacer()
            if missingCount > 0 {
                Button("Remove All Missing", action: actions.removeAllMissing)
            }
            Button("Open…", systemImage: "folder", action: actions.showOpenPanel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect)
    }

    /// A row's commands act on the whole selection when the row is part of it, as in the Finder.
    private func targets(of row: DashboardRow, selected: [DashboardRow]) -> [DashboardRow] {
        selected.contains(row) ? selected : [row]
    }

    @ViewBuilder
    private func contextMenu(for rows: [DashboardRow]) -> some View {
        Button(DashboardCommandTitle.open(rows.count)) { actions.open(rows) }
            .keyboardShortcut(.return, modifiers: [])
        if let row = rows.first, rows.count == 1, session.canShowInFinder(row) {
            Button(DashboardCommandTitle.showInFinder) { actions.showInFinder(row) }
                .keyboardShortcut(.return, modifiers: .command)
            Button(DashboardCommandTitle.setDisplayName) { actions.setDisplayName(row) }
        }
        Divider()
        Button(DashboardCommandTitle.remove(rows.count)) { actions.remove(rows) }
            .keyboardShortcut(.delete, modifiers: .command)
    }
}
