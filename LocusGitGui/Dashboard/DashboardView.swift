import SwiftUI

struct DashboardView: View {
    @Bindable var session: DashboardSession
    let onOpen: (DashboardRow) -> Void
    let onRemove: (DashboardRow) -> Void
    let onShowOpenPanel: () -> Void

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
            HStack {
                Button("Open…", systemImage: "folder", action: onShowOpenPanel)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect)
        }
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
        .onChange(of: session.openCount, initial: true) {
            // SwiftUI ignores a focus change made in the same pass the view appears in.
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
    }

    private var list: some View {
        let rows = session.rows
        let selectedID = session.selectedRow?.id
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(rows) { row in
                        DashboardRowView(row: row, state: session.states[row.id], isSelected: row.id == selectedID)
                            .id(row.id)
                            .contentShape(.rect)
                            .onTapGesture(count: 2) { onOpen(row) }
                            .simultaneousGesture(TapGesture().onEnded { session.select(row) })
                            .contextMenu { contextMenu(for: row) }
                    }
                }
                .padding(8)
            }
            .onChange(of: selectedID) {
                if let selectedID {
                    proxy.scrollTo(selectedID)
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

    @ViewBuilder
    private func contextMenu(for row: DashboardRow) -> some View {
        Button(session.states[row.id] == .missing ? "Locate…" : "Open") { onOpen(row) }
        Divider()
        Button("Remove from List") { onRemove(row) }
    }
}
