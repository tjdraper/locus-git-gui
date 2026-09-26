import SwiftUI

/// What the top of the detail column shows about the selected commit.
@Observable
final class CommitHeader {
    var commit: Commit?
    /// Nil until it's been read, and for a message that's only a subject.
    var body: String?
    var labels: [CommitRefLabel] = []
    /// Nil while it's being checked, which can take GPG a moment.
    var signature: CommitSignature?
    /// The signature couldn't be read, so the header leaves it out rather than guess.
    var isSignatureUnavailable = false
    /// Kept from one commit to the next, for someone who reads every message in full.
    var isMessageExpanded = false
    @ObservationIgnored var goToCommit: ((String) -> Void)?
    @ObservationIgnored var reveal: ((SidebarItemID) -> Void)?
}

/// The subject, which expands to the whole message, the commit's labels, and who made it, when,
/// and from which parents.
struct CommitHeaderView: View {
    /// A long message scrolls within this rather than pushing the changes out of the column.
    private static let longestMessage: CGFloat = 240

    let model: CommitHeader

    var body: some View {
        if let commit = model.commit {
            VStack(alignment: .leading, spacing: 10) {
                message(commit)
                if !model.labels.isEmpty {
                    RefLabelFlow(spacing: 4) {
                        ForEach(model.labels, id: \.self, content: label)
                    }
                }
                details(commit)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func message(_ commit: Commit) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(commit.subject.isEmpty ? "(No message)" : commit.subject)
                .font(.title3.weight(.semibold))
                .foregroundStyle(commit.subject.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.body != nil {
                Button {
                    model.isMessageExpanded.toggle()
                } label: {
                    Image(systemName: model.isMessageExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .help(model.isMessageExpanded ? "Hide Full Message" : "Show Full Message")
                .accessibilityLabel(model.isMessageExpanded ? "Hide Full Message" : "Show Full Message")
            }
        }
        if model.isMessageExpanded, let body = model.body {
            ScrollView {
                Text(body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Its own height up to the limit, rather than all the room it's offered.
            .frame(maxHeight: Self.longestMessage)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ label: CommitRefLabel) -> some View {
        Button {
            if let item = label.sidebarItem {
                model.reveal?(item)
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: RefLabelView.symbolName(for: label.kind))
                    .imageScale(.small)
                Text(label.name)
            }
            .font(.caption.weight(label.kind == .checkedOutBranch ? .semibold : .regular))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color(nsColor: RefLabelView.tint(for: label.kind)).opacity(0.2)))
        }
        .buttonStyle(.plain)
        .disabled(label.sidebarItem == nil)
        .help(label.sidebarItem == nil ? "" : "Reveal in Sidebar")
        .accessibilityLabel(RefLabelView.describe(label))
    }

    private func details(_ commit: Commit) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 4) {
            row("Author", Text(person(commit.author)))
            row("Date", Text(commit.author.date.formatted(date: .long, time: .shortened)))
            if commit.committer.name != commit.author.name || commit.committer.email != commit.author.email {
                row("Committer", Text(person(commit.committer)))
            }
            if commit.committer.date != commit.author.date {
                row("Committed", Text(commit.committer.date.formatted(date: .long, time: .shortened)))
            }
            row("Hash", Text(commit.hash).monospaced())
            if !model.isSignatureUnavailable {
                row("Signature", CommitSignatureText(signature: model.signature))
            }
            if !commit.parents.isEmpty {
                row(commit.parents.count == 1 ? "Parent" : "Parents", HStack(spacing: 8) {
                    ForEach(commit.parents, id: \.self) { parent in
                        Button(String(parent.prefix(7))) { model.goToCommit?(parent) }
                            .buttonStyle(.link)
                            .monospaced()
                            .help("Go to \(parent.prefix(7))")
                    }
                })
            }
        }
        .font(.callout)
    }

    private func row(_ title: String, _ value: some View) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            value
                .textSelection(.enabled)
        }
    }

    private func person(_ signature: Commit.Signature) -> String {
        signature.email.isEmpty ? signature.name : "\(signature.name) <\(signature.email)>"
    }
}

/// Lays out labels left to right, wrapping onto a new line when the column runs out of room.
private struct RefLabelFlow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.compactMap(\.last?.frame.maxX).max() ?? 0
        return CGSize(width: width, height: rows.last?.first?.frame.maxY ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for placement in arrange(subviews, width: bounds.width).joined() {
            subviews[placement.index].place(
                at: CGPoint(x: bounds.minX + placement.frame.minX, y: bounds.minY + placement.frame.minY),
                proposal: ProposedViewSize(placement.frame.size)
            )
        }
    }

    private struct Placement {
        let index: Int
        let frame: CGRect
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [[Placement]] {
        var rows: [[Placement]] = [[]]
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > width {
                origin = CGPoint(x: 0, y: origin.y + rowHeight + spacing)
                rowHeight = 0
                rows.append([])
            }
            rows[rows.count - 1].append(Placement(index: index, frame: CGRect(origin: origin, size: size)))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return rows
    }
}

/// A good signature gets a quiet green seal. Nothing else is shown as an error, since this Mac often
/// can't check a coworker's signature. Only a signature that doesn't match its commit gets a
/// warning mark, and even that stays in the secondary colour.
private struct CommitSignatureText: View {
    let signature: CommitSignature?

    var body: some View {
        if let signature {
            Label {
                Text(Self.describe(signature))
                    .foregroundStyle(signature.status == .good ? .primary : .secondary)
            } icon: {
                icon(for: signature.status)
            }
            .labelStyle(SignatureLabelStyle(hasIcon: signature.status != .unsigned))
            .help(signature.report ?? "")
        } else {
            Text("Checking…")
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func icon(for status: CommitSignature.Status) -> some View {
        switch status {
        case .good:
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        case .bad, .revokedKey:
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
        case .untrusted, .uncheckable, .expiredSignature, .expiredKey:
            Image(systemName: "seal").foregroundStyle(.secondary)
        case .unsigned:
            EmptyView()
        }
    }

    private static func describe(_ signature: CommitSignature) -> String {
        let signed = signature.signer.map { "Signed by \($0)" } ?? "Signed"
        return switch signature.status {
        case .good: signed
        case .untrusted: "\(signed) · key not trusted on this Mac"
        case .uncheckable: "Signed, but can’t be checked on this Mac"
        case .expiredSignature: "\(signed) · signature expired"
        case .expiredKey: "\(signed) · key expired"
        case .revokedKey: "\(signed) · key revoked"
        case .bad: "Signature doesn’t match this commit"
        case .unsigned: "Not signed"
        }
    }
}

/// "Not signed" has no icon, and shouldn't be indented as if it had one.
private struct SignatureLabelStyle: LabelStyle {
    let hasIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if hasIcon {
                configuration.icon
            }
            configuration.title
        }
    }
}
