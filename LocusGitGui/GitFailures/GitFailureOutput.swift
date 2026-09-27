import SwiftUI

/// The command and Git's own output, as tall as the output, scrolling once it's taller than the
/// most a sheet should take up. Fixing the capped frame at its ideal height is what makes the
/// scroll view fit its content instead of collapsing.
struct GitFailureOutput: View {
    let failure: GitFailure
    var maxHeight: CGFloat = 240

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("$ \(failure.commandLine)")
                    .foregroundStyle(.secondary)
                Text(failure.output.isEmpty ? "Git printed nothing, and exited with status \(failure.result.status)." : failure.output)
            }
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
    }
}
