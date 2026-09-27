import SwiftUI

/// Branches, remotes, tags and stashes, each in a section that collapses, under a field that filters
/// them. What's pinned has a section of its own at the top.
struct SidebarView: View {
    @Bindable var model: SidebarModel
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            list
                .onChange(of: model.revealRequests) {
                    // After the section or remote it's in has expanded.
                    DispatchQueue.main.async {
                        if let selection = model.selection {
                            proxy.scrollTo(selection)
                        }
                    }
                }
        }
    }

    private var list: some View {
        List(selection: $model.selection) {
            if let contents = model.visibleContents {
                if !contents.pinned.isEmpty {
                    section(.pinned) {
                        ForEach(contents.pinned) { item in
                            SidebarPinnedRow(item: item)
                                .modifier(SidebarBranchDragging(id: item.id, model: model))
                        }
                    }
                }
                if !contents.unpinnedBranches.isEmpty {
                    section(.branches) {
                        ForEach(contents.unpinnedBranches) { branch in
                            SidebarBranchRow(branch: branch)
                                .modifier(SidebarBranchDragging(id: branch.id, model: model))
                        }
                    }
                }
                if !contents.unpinnedRemotes.isEmpty {
                    section(.remotes) {
                        ForEach(contents.unpinnedRemotes) { remote in
                            DisclosureGroup(isExpanded: remoteExpansion(remote.name)) {
                                ForEach(remote.branches) { branch in
                                    Label(branch.name, systemImage: "arrow.triangle.branch")
                                        .modifier(SidebarBranchDragging(id: branch.id, model: model))
                                }
                            } label: {
                                Label(remote.name, systemImage: "network")
                            }
                        }
                    }
                }
                if !contents.unpinnedTags.isEmpty {
                    section(.tags) {
                        ForEach(contents.unpinnedTags) { tag in
                            SidebarTagRow(tag: tag)
                                .modifier(SidebarBranchDragging(id: tag.id, model: model))
                        }
                    }
                }
                if !contents.unpinnedStashes.isEmpty {
                    section(.stashes) {
                        ForEach(contents.unpinnedStashes, content: SidebarStashRow.init)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: SidebarItemID.self) { ids in
            if ids.count == 1, let id = ids.first {
                menu(for: id)
            }
        } primaryAction: { ids in
            if ids.count == 1, let id = ids.first {
                model.primaryAction?(id)
            }
        }
        .focused($isFocused)
        .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters).union(.symbols)) { press in
            guard press.modifiers.isDisjoint(with: [.command, .control]) else { return .ignored }
            model.typeSelect(press.characters)
            return .handled
        }
        .onChange(of: model.focusRequests, initial: true) {
            // SwiftUI ignores a focus change made in the same pass the view appears in.
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        // Outside the list's key handling, which would otherwise take the field's typing for
        // type-to-select.
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarFilterField(
                text: $model.filter,
                focusRequests: model.filterFocusRequests,
                moveToList: model.requestFocus
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .overlay {
            if model.isFiltering, model.visibleContents?.isEmpty == true {
                ContentUnavailableView.search(text: model.filter)
            }
        }
    }

    @ViewBuilder
    private func menu(for id: SidebarItemID) -> some View {
        Button(AppCommand.openCommitInNewWindow.title) {
            model.openInNewWindow?(id)
        }
        if SidebarPins.canPin(id) {
            Button(SidebarPinWorkflow.title(isPinned: model.pins.contains(id))) {
                model.togglePin(id)
            }
        }
        let groups = model.menuItems?(id) ?? []
        ForEach(groups.indices, id: \.self) { index in
            Divider()
            ForEach(groups[index]) { item in
                Button(item.title, action: item.action)
                    .disabled(!item.isEnabled)
            }
        }
    }

    private func section(_ section: SidebarSection, @ViewBuilder rows: () -> some View) -> some View {
        Section(section.title, isExpanded: Binding(
            get: { model.isExpanded(section) },
            set: { model.setExpanded($0, section) }
        ), content: rows)
    }

    private func remoteExpansion(_ remote: String) -> Binding<Bool> {
        Binding(
            get: { model.isExpanded(remote: remote) },
            set: { model.setExpanded($0, remote: remote) }
        )
    }
}

/// A branch, remote branch or tag dragged onto a branch asks whether to merge or rebase. Only refs
/// are dragged, as text naming the ref, which anything outside the app can't take for one.
private struct SidebarBranchDragging: ViewModifier {
    private static let prefix = "locus-git-gui-ref:"

    let id: SidebarItemID
    let model: SidebarModel

    func body(content: Content) -> some View {
        if case let .ref(name) = id {
            content
                .draggable(Self.prefix + name)
                .dropDestination(for: String.self) { items, _ in
                    guard let text = items.first, text.hasPrefix(Self.prefix) else { return false }
                    let dragged = SidebarItemID.ref(String(text.dropFirst(Self.prefix.count)))
                    guard dragged != id else { return false }
                    model.drop?(dragged, id)
                    return true
                }
        } else {
            content
        }
    }
}

private struct SidebarPinnedRow: View {
    let item: SidebarContents.PinnedItem

    var body: some View {
        switch item {
        case let .branch(branch):
            SidebarBranchRow(branch: branch)
        case let .remoteBranch(_, name):
            Label(name, systemImage: "arrow.triangle.branch")
        case let .tag(tag):
            SidebarTagRow(tag: tag)
        case let .stash(stash):
            SidebarStashRow(stash: stash)
        }
    }
}

private struct SidebarTagRow: View {
    let tag: SidebarContents.Tag

    var body: some View {
        Label(tag.name, systemImage: "tag")
    }
}

private struct SidebarStashRow: View {
    let stash: SidebarContents.StashEntry

    var body: some View {
        Label(stash.message, systemImage: "archivebox")
            .help(stash.date.formatted(date: .abbreviated, time: .shortened))
    }
}

private struct SidebarBranchRow: View {
    let branch: SidebarContents.Branch

    var body: some View {
        Label {
            HStack {
                Text(branch.name)
                    .fontWeight(branch.isCheckedOut ? .semibold : nil)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                tracking
            }
        } icon: {
            Image(systemName: branch.isCheckedOut ? "checkmark.circle.fill" : "arrow.triangle.branch")
        }
        .accessibilityValue(branch.isCheckedOut ? "Checked out" : "")
    }

    /// Nothing when the branch is level with its upstream, which is the usual case.
    @ViewBuilder private var tracking: some View {
        if branch.isUpstreamGone {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .help("\(branch.upstream ?? "The upstream branch") no longer exists on the remote.")
        } else if let upstream = branch.upstream, let ahead = branch.ahead, let behind = branch.behind, ahead + behind > 0 {
            HStack(spacing: 4) {
                if ahead > 0 {
                    Text("\(ahead)\(Image(systemName: "arrow.up"))")
                }
                if behind > 0 {
                    Text("\(behind)\(Image(systemName: "arrow.down"))")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .help(Self.describe(ahead: ahead, behind: behind, upstream: upstream))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.describe(ahead: ahead, behind: behind, upstream: upstream))
        }
    }

    private static func describe(ahead: Int, behind: Int, upstream: String) -> String {
        switch (ahead, behind) {
        case (0, _): "\(commits(behind)) behind \(upstream)"
        case (_, 0): "\(commits(ahead)) ahead of \(upstream)"
        default: "\(ahead) ahead of \(upstream), \(behind) behind"
        }
    }

    private static func commits(_ count: Int) -> String {
        count == 1 ? "1 commit" : "\(count) commits"
    }
}
