import AppKit

/// Where the diff was left, for whoever shows it to remember and show it there again.
extension DiffViewController {
    private static let placeReportDelay: Duration = .milliseconds(300)

    var place: DiffPlace {
        let top = canvas.visibleRect.minY
        let scroll = pendingScroll ?? (top > 0 ? canvas.content.flatMap { content in
            DiffScrollAnchor(top: top, document: content.document, layout: content.layout, files: content.files)
        } : nil)
        return DiffPlace(collapsed: collapsedFiles, picked: selectedFiles, pickAnchor: selectionAnchor, marked: markedFile, scroll: scroll)
    }

    /// For a diff shown before it was read, once it has been.
    func scroll(to anchor: DiffScrollAnchor) {
        pendingScroll = anchor
        rebuild(keepingPlace: false)
    }

    /// A moment later, since scrolling changes it many times a second.
    func placeDidChange() {
        guard onPlaceChange != nil, reportingPlace == nil else { return }
        reportingPlace = Task { [weak self] in
            try? await Task.sleep(for: Self.placeReportDelay)
            guard !Task.isCancelled else { return }
            self?.reportPlaceNow()
        }
    }

    /// Before the diff shows other files, while whoever shows it still knows which diff this was.
    func reportPlaceNow() {
        guard let reporting = reportingPlace else { return }
        reporting.cancel()
        reportingPlace = nil
        onPlaceChange?(place)
    }
}
