import AppKit
import SwiftUI

/// A bar at the top of the conflict window while a merge, rebase, cherry-pick or revert waits
/// partway, with Continue, Skip and Abort. The window exists only while one does, so the bar never
/// comes and goes under the user.
struct OperationBar: View {
    let status: OperationStatus

    var body: some View {
        VStack(spacing: 0) {
            if let stopped = status.stopped {
                bar {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stopped.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(stopped.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Abort…") { status.abort?() }
                        .controlSize(.small)
                    if stopped.kind != .merge {
                        Button("Skip") { status.skip?() }
                            .controlSize(.small)
                    }
                    Button("Continue") { status.continueOperation?() }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func bar(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8, content: content)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor))
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
    }
}
