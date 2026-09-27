import SwiftUI

/// Every failure behind the toolbar's warning, when the app has failed at more than one thing on its
/// own, such as a refresh and an automatic fetch. Each has its explanation and Git's output.
struct GitFailureListSheet: View {
    let failures: [GitFailure]
    let repository: Repository
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(failures.count) things went wrong in this repository")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(failures.enumerated()), id: \.offset) { _, failure in
                        HStack(alignment: .top, spacing: 14) {
                            GitFailureSymbol(failure: failure)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(failure.summary)
                                    .font(.headline)
                                GitFailureExplanation(failure: failure, repository: repository)
                                    .fixedSize(horizontal: false, vertical: true)
                                GitFailureOutput(failure: failure, maxHeight: 160)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 520)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(failures.map(\.transcript).joined(separator: "\n\n"), forType: .string)
                }
                Spacer()
                Button("Try Again") {
                    dismiss()
                    retry()
                }
                Button("Done", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 600)
    }
}
