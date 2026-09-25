import AppKit
import SwiftUI

/// What the title shows, changed as the repository's display name and state are read.
@Observable
final class RepositoryTitle {
    var displayName: String?
    var subtitle = ""
    let path: String

    init(path: String, displayName: String?) {
        self.path = path
        self.displayName = displayName
    }
}

/// The window's title and subtitle, drawn in the toolbar because AppKit's own title can only cut a
/// long path from the right, which hides the folders that tell repositories apart.
struct RepositoryTitleView: View {
    let title: RepositoryTitle
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let displayName = title.displayName {
                    Text(displayName)
                        .font(Font(NSFont.titleBarFont(ofSize: 0)))
                        .foregroundStyle(primaryStyle)
                        .layoutPriority(1)
                    // The parentheses stay whole however much of the path is cut.
                    HStack(spacing: 0) {
                        Text(verbatim: "(")
                        Text(title.path).truncationMode(.head)
                        Text(verbatim: ")")
                    }
                    .font(.system(size: NSFont.smallSystemFontSize))
                    .foregroundStyle(secondaryStyle)
                } else {
                    Text(title.path)
                        .font(Font(NSFont.titleBarFont(ofSize: 0)))
                        .foregroundStyle(primaryStyle)
                        .truncationMode(.head)
                }
            }
            // A space keeps the line's height before the first refresh fills it in.
            Text(title.subtitle.isEmpty ? " " : title.subtitle)
                .font(.system(size: NSFont.smallSystemFontSize))
                .foregroundStyle(secondaryStyle)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    /// A window in the background dims its title, as AppKit's own does.
    private var primaryStyle: HierarchicalShapeStyle {
        appearsActive ? .primary : .tertiary
    }

    private var secondaryStyle: HierarchicalShapeStyle {
        appearsActive ? .secondary : .tertiary
    }
}
