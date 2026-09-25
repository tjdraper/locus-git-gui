import AppKit

@main
enum LocusGitGuiApp {
    /// `NSApplication.delegate` does not retain, so the delegate is held here instead.
    private static let delegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = delegate
        application.run()
    }
}
