import SwiftUI

/// What the review compares: the base, and what's compared with it. Either can be changed at any
/// time, and the review follows.
struct ReviewPointsView: View {
    let session: ReviewSession
    let review: Review
    let chooseCommit: (_ isBase: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("Compare")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    menu(for: review.head, isBase: false)
                }
                GridRow {
                    Text("With")
                        .foregroundStyle(.secondary)
                    menu(for: review.base, isBase: true)
                }
            }
            if !review.missingPoints.isEmpty {
                Label(missingMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var missingMessage: String {
        let names = review.missingPoints.map { "“\($0.title)”" }.sorted().formatted(.list(type: .and))
        let verb = review.missingPoints.count == 1 ? "is" : "are"
        return review.revision == nil
            ? "\(names) \(verb) gone."
            : "\(names) \(verb) gone, so the review shows where it last was."
    }

    private func menu(for point: ReviewPoint, isBase: Bool) -> some View {
        Menu {
            pointChoices(isBase: isBase)
        } label: {
            Text(point.title)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .help(point.title)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pointChoices(isBase: Bool) -> some View {
        let refs = session.refs.filter { $0.symbolicTarget == nil }
        let local = refs.filter { $0.kind == .localBranch }
        let remote = Dictionary(grouping: refs.filter { $0.kind == .remoteBranch }) { ref in
            ReviewPoint.shortName(of: ref.name).split(separator: "/").first.map(String.init) ?? ""
        }
        let tags = refs.filter { $0.kind == .tag }
        if !isBase {
            Button("Uncommitted Changes") { choose(.workingTree, isBase: isBase) }
        }
        Button("HEAD (the Checked-Out Commit)") { choose(.checkedOut, isBase: isBase) }
        Divider()
        Section("Branches") {
            ForEach(local, id: \.name) { ref in
                Button(ReviewPoint.shortName(of: ref.name)) { choose(.ref(ref.name), isBase: isBase) }
            }
        }
        ForEach(remote.keys.sorted(), id: \.self) { remoteName in
            Menu(remoteName) {
                ForEach(remote[remoteName] ?? [], id: \.name) { ref in
                    Button(String(ReviewPoint.shortName(of: ref.name).dropFirst(remoteName.count + 1))) {
                        choose(.ref(ref.name), isBase: isBase)
                    }
                }
            }
        }
        if !tags.isEmpty {
            Menu("Tags") {
                ForEach(tags, id: \.name) { ref in
                    Button(ReviewPoint.shortName(of: ref.name)) { choose(.ref(ref.name), isBase: isBase) }
                }
            }
        }
        Divider()
        Button("Commit…") { chooseCommit(isBase) }
        let point = isBase ? review.base : review.head
        if case let .commit(hash) = point, let branches = session.containing[hash], !branches.isEmpty {
            Section("Move to the Latest Commit On") {
                ForEach(branches, id: \.name) { ref in
                    Button(ReviewPoint.shortName(of: ref.name)) { choose(.commit(ref.commit), isBase: isBase) }
                }
            }
        }
    }

    private func choose(_ point: ReviewPoint, isBase: Bool) {
        session.setPoints(base: isBase ? point : review.base, head: isBase ? review.head : point)
    }
}
