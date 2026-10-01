import SwiftUI

/// What the review compares, in the window's toolbar: what's compared, and what it's compared
/// with. Either can be changed at any time, and the review follows.
struct ReviewPointsView: View {
    let session: ReviewSession
    let chooseCommit: (_ isBase: Bool) -> Void

    var body: some View {
        if let review = session.review {
            HStack(spacing: 6) {
                Text("Compare")
                    .foregroundStyle(.secondary)
                menu(for: review.head, isBase: false, in: review)
                Text("with")
                    .foregroundStyle(.secondary)
                menu(for: review.base, isBase: true, in: review)
            }
            // The toolbar draws its glass to the item's edges, so the room inside it is the item's own.
            .padding(.horizontal, 12)
            .fixedSize()
        }
    }

    private func menu(for point: ReviewPoint, isBase: Bool, in review: Review) -> some View {
        Menu {
            pointChoices(isBase: isBase, in: review)
        } label: {
            Text(point.title)
                .lineLimit(1)
        }
        .help(isBase ? "What the review compares with" : "What the review compares")
    }

    @ViewBuilder
    private func pointChoices(isBase: Bool, in review: Review) -> some View {
        let refs = session.refs.filter { $0.symbolicTarget == nil }
        let local = refs.filter { $0.kind == .localBranch }
        let remote = Dictionary(grouping: refs.filter { $0.kind == .remoteBranch }) { ref in
            ReviewPoint.shortName(of: ref.name).split(separator: "/").first.map(String.init) ?? ""
        }
        let tags = refs.filter { $0.kind == .tag }
        if !isBase {
            Button("Uncommitted Changes") { choose(.workingTree, isBase: isBase, in: review) }
        }
        Button("HEAD (the Checked-Out Commit)") { choose(.checkedOut, isBase: isBase, in: review) }
        Divider()
        Section("Branches") {
            ForEach(local, id: \.name) { ref in
                Button(ReviewPoint.shortName(of: ref.name)) { choose(.ref(ref.name), isBase: isBase, in: review) }
            }
        }
        ForEach(remote.keys.sorted(), id: \.self) { remoteName in
            Menu(remoteName) {
                ForEach(remote[remoteName] ?? [], id: \.name) { ref in
                    Button(String(ReviewPoint.shortName(of: ref.name).dropFirst(remoteName.count + 1))) {
                        choose(.ref(ref.name), isBase: isBase, in: review)
                    }
                }
            }
        }
        if !tags.isEmpty {
            Menu("Tags") {
                ForEach(tags, id: \.name) { ref in
                    Button(ReviewPoint.shortName(of: ref.name)) { choose(.ref(ref.name), isBase: isBase, in: review) }
                }
            }
        }
        Divider()
        Button("Commit…") { chooseCommit(isBase) }
        let point = isBase ? review.base : review.head
        if case let .commit(hash) = point, let branches = session.containing[hash], !branches.isEmpty {
            Section("Move to the Latest Commit On") {
                ForEach(branches, id: \.name) { ref in
                    Button(ReviewPoint.shortName(of: ref.name)) { choose(.commit(ref.commit), isBase: isBase, in: review) }
                }
            }
        }
    }

    private func choose(_ point: ReviewPoint, isBase: Bool, in review: Review) {
        session.setPoints(base: isBase ? point : review.base, head: isBase ? review.head : point)
    }
}

/// Above the review's files when a branch it follows is gone, such as after its pull request was
/// merged.
struct ReviewMissingPointsNotice: View {
    let review: Review

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .symbolRenderingMode(.multicolor)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var message: String {
        let names = review.missingPoints.map { "“\($0.title)”" }.sorted().formatted(.list(type: .and))
        let verb = review.missingPoints.count == 1 ? "is" : "are"
        return review.revision == nil
            ? "\(names) \(verb) gone."
            : "\(names) \(verb) gone, so the review shows where it last was."
    }
}
