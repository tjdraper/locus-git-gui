import SwiftUI

/// Branches, remotes, tags and stashes, each in a section that collapses, under a field that filters
/// them.
struct SidebarView: View {
    @Bindable var model: SidebarModel
    @FocusState private var isFocused: Bool

    var body: some View {
        List(selection: $model.selection) {
            if let contents = model.visibleContents {
                if !contents.branches.isEmpty {
                    section(.branches) {
                        ForEach(contents.branches, content: SidebarBranchRow.init)
                    }
                }
                if !contents.remotes.isEmpty {
                    section(.remotes) {
                        ForEach(contents.remotes) { remote in
                            DisclosureGroup(isExpanded: remoteExpansion(remote.name)) {
                                ForEach(remote.branches) { branch in
                                    Label(branch.name, systemImage: "arrow.triangle.branch")
                                }
                            } label: {
                                Label(remote.name, systemImage: "network")
                            }
                        }
                    }
                }
                if !contents.tags.isEmpty {
                    section(.tags) {
                        ForEach(contents.tags) { tag in
                            Label(tag.name, systemImage: "tag")
                        }
                    }
                }
                if !contents.stashes.isEmpty {
                    section(.stashes) {
                        ForEach(contents.stashes) { stash in
                            Label(stash.message, systemImage: "archivebox")
                                .help(stash.date.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
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
