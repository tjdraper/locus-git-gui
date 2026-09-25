import SwiftUI

struct ApplicationsFolderRow: View {
    private let workflow = ApplicationsFolderMoveWorkflow()

    var body: some View {
        LabeledContent {
            if workflow.location.isInApplicationsFolder {
                Label {
                    Text("Done")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Button("Move to Applications") {
                    workflow.move()
                }
            }
        } label: {
            Text("Applications folder")
            Text(workflow.location.isInApplicationsFolder
                ? "Locus Git Gui can update itself."
                : "Locus Git Gui needs to be in Applications to update itself. Moving it relaunches the app.")
        }
    }
}
