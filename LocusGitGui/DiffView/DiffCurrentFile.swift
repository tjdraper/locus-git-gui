import AppKit

/// The file the keyboard acts on: the one with the selection in it, the one Next File or Previous
/// File went to, or the one at the top. J and K move through the files, as in a mail or news reader,
/// since the diff has nothing to type into.
extension DiffViewController {
    static let nextFileKey = "j"
    static let previousFileKey = "k"

    func typed(_ key: String) -> Bool {
        if onTypedKey?(key) == true {
            return true
        }
        switch key {
        case Self.nextFileKey: goToFile(offset: 1)
        case Self.previousFileKey: goToFile(offset: -1)
        default: return false
        }
        return true
    }

    /// A click in another file's lines, or scrolling the marked file away, hands the keyboard back to
    /// the file at the top.
    func forgetMarkedFileOutOfView() {
        guard let target = commandTarget, let marked = target.markedFile, !target.isInView(file: marked) else { return }
        markedFile = nil
    }

    func scrollToMarkedFileIfOutOfView() {
        guard let content = canvas.content, let target = commandTarget, let marked = target.markedFile,
              !target.isInView(file: marked) else { return }
        canvas.scroll(to: content.layout.top(of: content.document.fileStarts[marked]))
        blockViews.update()
    }
}
