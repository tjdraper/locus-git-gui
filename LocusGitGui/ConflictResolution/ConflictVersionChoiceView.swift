import SwiftUI

/// For a conflict that isn't in the file's lines, such as a file deleted on one side and changed on
/// the other: why there's nothing to combine, and the versions to choose between.
struct ConflictVersionChoiceView: View {
    let options: ConflictVersionOptions
    let choose: (ConflictVersionChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(options.explanation)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                ForEach(options.options, id: \.choice) { option in
                    GridRow {
                        Button {
                            choose(option.choice)
                        } label: {
                            Text(option.title)
                                .lineLimit(1)
                        }
                        Text(option.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// What shows in place of the versions while there's no file to resolve: a file being read, one that
/// couldn't be, or every conflict resolved.
struct ConflictMessageView: View {
    let state: ConflictEditorState

    var body: some View {
        Group {
            switch state.mode {
            case let .empty(message):
                Text(message)
                    .foregroundStyle(.secondary)
            case .reading:
                ProgressView()
                    .controlSize(.small)
            case let .failed(message):
                VStack(spacing: 8) {
                    Text(message)
                        .foregroundStyle(.secondary)
                    Button("Show Details") { state.showFailureDetails?() }
                }
            case .editing, .choosing:
                EmptyView()
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
