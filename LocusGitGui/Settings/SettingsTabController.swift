import AppKit
import SwiftUI

/// The panes, switched from the toolbar as in any Mac app's settings. The window takes each pane's
/// height, and grows or shrinks with it, such as when the Git step shows the other Gits found.
final class SettingsTabController: NSTabViewController {
    private static let paneKey = "SettingsPane"

    init(panes: [(SettingsPane, NSHostingController<AnyView>)]) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        // The window's own frame change does the animating, and the default crossfade flickers
        // against it.
        transitionOptions = []
        for (pane, controller) in panes {
            controller.title = pane.title
            controller.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            item.identifier = pane.rawValue
            item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
            addTabViewItem(item)
        }
        let remembered = UserDefaults.standard.string(forKey: Self.paneKey).flatMap(SettingsPane.init)
        selectedTabViewItemIndex = remembered.flatMap { pane in panes.firstIndex { $0.0 == pane } } ?? 0
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let pane = tabViewItem?.identifier as? String {
            UserDefaults.standard.set(pane, forKey: Self.paneKey)
        }
        fitWindow(animated: view.window?.isVisible == true)
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        guard viewController === tabViewItems[safe: selectedTabViewItemIndex]?.viewController else { return }
        fitWindow(animated: view.window?.isVisible == true)
    }

    /// Keeps the window's top edge where it is, as the title bar is what the eye follows.
    func fitWindow(animated: Bool) {
        guard let window = view.window,
              let pane = tabViewItems[safe: selectedTabViewItemIndex]?.viewController
        else { return }
        let size = pane.preferredContentSize == .zero ? pane.view.fittingSize : pane.preferredContentSize
        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        let frame = NSRect(
            x: window.frame.minX,
            y: window.frame.maxY - frameSize.height,
            width: frameSize.width,
            height: frameSize.height
        )
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true, animate: animated)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
