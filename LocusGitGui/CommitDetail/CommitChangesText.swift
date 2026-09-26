import AppKit

/// A commit's changed files and their changes as styled text: each file's name as a heading, then
/// its changes in a fixed-width font, added lines in green and removed lines in red.
enum CommitChangesText {
    private static let codeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let headingFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

    static func make(_ detail: CommitDetail) -> NSAttributedString {
        let text = NSMutableAttributedString()
        guard !detail.files.isEmpty || !detail.patch.files.isEmpty else {
            append("This commit changes no files.", to: text, font: headingFont, color: .secondaryLabelColor)
            return text
        }
        // `--name-status` and `--patch` list files in the same order. Should they ever disagree
        // in count, every file and every change is still shown.
        for index in 0 ..< max(detail.files.count, detail.patch.files.count) {
            if detail.files.indices.contains(index) {
                append(heading(detail.files[index]), to: text, font: headingFont, color: .labelColor, spaceBefore: index > 0 ? 14 : 0)
            }
            if detail.patch.files.indices.contains(index) {
                for line in detail.patch.files[index] {
                    append(line.text, to: text, font: codeFont, color: color(of: line.kind))
                }
            }
        }
        if detail.patch.isShortened {
            append(
                "The rest of this commit’s changes are too large to show here.",
                to: text,
                font: headingFont,
                color: .secondaryLabelColor,
                spaceBefore: 14
            )
        }
        return text
    }

    private static func heading(_ file: ChangedFile) -> String {
        if let originalPath = file.originalPath {
            return "\(file.change.title)  \(originalPath) → \(file.path)"
        }
        return "\(file.change.title)  \(file.path)"
    }

    /// System colours, which adjust themselves for dark mode.
    private static func color(of kind: CommitPatchLine.Kind) -> NSColor {
        switch kind {
        case .added: .systemGreen
        case .removed: .systemRed
        case .hunkHeader, .fileInfo: .secondaryLabelColor
        case .note: .tertiaryLabelColor
        case .context: .labelColor
        }
    }

    private static func append(_ line: String, to text: NSMutableAttributedString, font: NSFont, color: NSColor, spaceBefore: CGFloat = 0) {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if spaceBefore > 0 {
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacingBefore = spaceBefore
            attributes[.paragraphStyle] = paragraph
        }
        text.append(NSAttributedString(string: line + "\n", attributes: attributes))
    }
}
