import SwiftUI

/// In place of a file's changes while several files are picked: how many, and what can be done
/// to them all at once.
struct ReviewSelectionView: View {
    let session: ReviewSession

    var body: some View {
        let picked = session.selectedEntries
        let reviewed = picked.count { $0.state == .checked }
        VStack(spacing: 12) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("\(picked.count.formatted()) Files Selected")
                .font(.title3.weight(.semibold))
            Text("\(reviewed.formatted()) of them reviewed")
                .foregroundStyle(.secondary)
            HStack {
                Button(Self.reviewedTitle(count: picked.count, isReviewed: false)) {
                    session.setReviewed(Set(picked.map(\.file.path)), true)
                }
                .disabled(reviewed == picked.count)
                Button(Self.reviewedTitle(count: picked.count, isReviewed: true)) {
                    session.setReviewed(Set(picked.map(\.file.path)), false)
                }
                .disabled(reviewed == 0)
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// "Mark as Reviewed" for one file, "Mark 3 Files as Reviewed" for several, and "Not
    /// Reviewed" for files that already are.
    static func reviewedTitle(count: Int, isReviewed: Bool) -> String {
        let state = isReviewed ? "Not Reviewed" : "Reviewed"
        return count > 1 ? "Mark \(count.formatted()) Files as \(state)" : "Mark as \(state)"
    }
}
