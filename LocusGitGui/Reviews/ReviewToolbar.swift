import AppKit
import SwiftUI

/// The review window's toolbar: what's compared, and commenting on and renaming the review.
final class ReviewToolbar: NSObject, NSToolbarDelegate {
    private static let pointsItem = NSToolbarItem.Identifier("ReviewPoints")
    private static let commentItem = NSToolbarItem.Identifier("CommentOnReview")
    private static let renameItem = NSToolbarItem.Identifier("RenameReview")

    let toolbar = NSToolbar(identifier: "ReviewWindow")
    private let session: ReviewSession
    private let chooseCommit: (_ isBase: Bool) -> Void
    private let commentOnReview: () -> Void
    private let rename: () -> Void

    init(
        session: ReviewSession,
        chooseCommit: @escaping (_ isBase: Bool) -> Void,
        commentOnReview: @escaping () -> Void,
        rename: @escaping () -> Void
    ) {
        self.session = session
        self.chooseCommit = chooseCommit
        self.commentOnReview = commentOnReview
        self.rename = rename
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.pointsItem, .flexibleSpace, Self.commentItem, Self.renameItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case Self.pointsItem:
            item.view = NSHostingView(rootView: ReviewPointsView(session: session, chooseCommit: chooseCommit))
            item.label = "Compare"
        case Self.commentItem:
            item.label = AppCommand.commentOnReview.title
            item.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: item.label)
            item.action = #selector(commentClicked(_:))
            item.target = self
            item.isBordered = true
        case Self.renameItem:
            item.label = "Rename Review"
            item.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: item.label)
            item.action = #selector(renameClicked(_:))
            item.target = self
            item.isBordered = true
        default:
            return nil
        }
        item.toolTip = item.label
        return item
    }

    @objc private func commentClicked(_: Any?) {
        commentOnReview()
    }

    @objc private func renameClicked(_: Any?) {
        rename()
    }
}
