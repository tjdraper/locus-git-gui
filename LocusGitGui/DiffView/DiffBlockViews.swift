import AppKit

/// The views laid over the diff where drawing isn't enough: file headers with their buttons, notices
/// that offer to show left-out changes, and images. Only the ones on screen exist, placed as the diff
/// scrolls. A file's header stays at the top while any of the file is in view, until the next
/// file's header pushes it up.
final class DiffBlockViews {
    var configureHeader: ((DiffFileHeaderView, _ file: Int) -> Void)?
    var configureNotice: ((DiffNoticeView, _ file: Int, DiffDocument.Notice) -> Void)?
    var configureImages: ((DiffImagesView, _ file: Int) -> Void)?

    private let canvas: DiffCanvasView
    private var headers: [Int: DiffFileHeaderView] = [:]
    private var notices: [Int: DiffNoticeView] = [:]
    private var images: [Int: DiffImagesView] = [:]
    private var spareHeaders: [DiffFileHeaderView] = []
    private var spareNotices: [DiffNoticeView] = []
    private var spareImages: [DiffImagesView] = []

    init(canvas: DiffCanvasView) {
        self.canvas = canvas
    }

    /// Everything goes when the diff changes, since a block's index then means something else.
    func removeAll() {
        for view in headers.values {
            view.removeFromSuperview()
            spareHeaders.append(view)
        }
        for view in notices.values {
            view.removeFromSuperview()
            spareNotices.append(view)
        }
        for view in images.values {
            view.removeFromSuperview()
            spareImages.append(view)
        }
        headers = [:]
        notices = [:]
        images = [:]
    }

    func update() {
        guard let content = canvas.content else {
            removeAll()
            return
        }
        let visible = canvas.visibleRect
        let layout = content.layout
        let document = content.document
        let blocks = layout.blocks(from: visible.minY, to: visible.maxY)
        var shownFiles = Set<Int>()
        var shownNotices = Set<Int>()
        var shownImages = Set<Int>()
        for block in blocks {
            let frame = layout.frame(of: block)
            let rect = NSRect(x: 0, y: frame.minY, width: canvas.bounds.width, height: frame.maxY - frame.minY)
            switch document.blocks[block] {
            case let .notice(file, notice):
                shownNotices.insert(block)
                let view = notices[block] ?? add(from: &spareNotices, below: true, make: DiffNoticeView.init)
                notices[block] = view
                view.frame = rect
                configureNotice?(view, file, notice)
            case let .images(file):
                shownImages.insert(file)
                let view = images[file] ?? add(from: &spareImages, below: true, make: DiffImagesView.init)
                images[file] = view
                view.frame = rect
                configureImages?(view, file)
            default:
                break
            }
            shownFiles.insert(document.blocks[block].file)
        }
        for file in shownFiles {
            let headerTop = layout.top(of: document.fileStarts[file])
            let fileEnd = file + 1 < document.fileStarts.count ? layout.top(of: document.fileStarts[file + 1]) : layout.height
            let height = layout.metrics.headerHeight
            let y = min(max(visible.minY, headerTop), fileEnd - height)
            let view = headers[file] ?? add(from: &spareHeaders, below: false, make: DiffFileHeaderView.init)
            headers[file] = view
            view.frame = NSRect(x: 0, y: y, width: canvas.bounds.width, height: height)
            configureHeader?(view, file)
        }
        retire(&headers, keeping: shownFiles, into: &spareHeaders)
        retire(&notices, keeping: shownNotices, into: &spareNotices)
        retire(&images, keeping: shownImages, into: &spareImages)
    }

    /// Notices and images go under the headers, which slide over them while stuck at the top.
    private func add<View: NSView>(from spares: inout [View], below: Bool, make: (NSRect) -> View) -> View {
        let view = spares.popLast() ?? make(.zero)
        canvas.addSubview(view, positioned: below ? .below : .above, relativeTo: nil)
        return view
    }

    private func retire<View: NSView>(_ views: inout [Int: View], keeping kept: Set<Int>, into spares: inout [View]) {
        for (key, view) in views where !kept.contains(key) {
            view.removeFromSuperview()
            spares.append(view)
            views[key] = nil
        }
    }
}
