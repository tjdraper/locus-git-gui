import AppKit
import SwiftUI

/// A bar above the history while a fetch, pull or push runs: what it's doing, how far it has got,
/// and Cancel. It takes no room while nothing runs.
struct RemoteProgressBar: View {
    let model: RemoteProgress

    var body: some View {
        if let running = model.running {
            bar {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(running.title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        if let progress = running.progress {
                            Text(progress.summary)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    .font(.callout)
                    if let fraction = running.progress?.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }
                Button("Cancel", systemImage: "xmark.circle.fill", action: running.cancel)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Stop \(running.title.lowercasedFirstWord)")
            }
        } else if let notice = model.notice {
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
                Button("Close", systemImage: "xmark.circle.fill", action: model.dismissNotice)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
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

extension String {
    /// “Pushing “main” to “origin”” as “pushing “main” to “origin””, to follow “Stop”.
    fileprivate var lowercasedFirstWord: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
