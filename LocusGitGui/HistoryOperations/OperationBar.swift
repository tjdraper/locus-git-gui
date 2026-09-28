import AppKit
import SwiftUI

/// A bar above the history while a merge, rebase, cherry-pick or revert waits partway, with
/// Continue, Skip and Abort, and after a destructive command, the commit that brings back what it
/// took away. It takes no room otherwise.
struct OperationBar: View {
    let status: OperationStatus
    /// The conflict window shows only the stopped operation, since a notice is about the history.
    var showsNotice = true

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
            if showsNotice, let notice = status.notice {
                bar {
                    Text(notice.message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Copy Hash") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(notice.hash, forType: .string)
                    }
                    .controlSize(.small)
                    Button("Close", systemImage: "xmark.circle.fill", action: status.dismissNotice)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
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
