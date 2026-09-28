import SwiftUI

extension TrialNotice.Urgency {
    /// System colours, which adjust themselves for dark mode. Nil for the first two weeks, when the
    /// notice is only information.
    var color: Color? {
        switch self {
        case .none: nil
        case .low: .yellow
        case .medium: .orange
        case .high: .red
        }
    }
}

struct TrialNoticeIcon: View {
    let notice: TrialNotice?

    var body: some View {
        switch notice {
        case .ended:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Trial ended")
        case let notice?:
            Image(systemName: "hourglass")
                .foregroundStyle(notice.urgency.color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .accessibilityLabel("Trial")
        case nil:
            EmptyView()
        }
    }
}

/// Purchase…, in the notice's colour once the end is near, and quiet before that.
struct PurchaseButton: View {
    enum Placement {
        /// The toolbar's glass, where SwiftUI drops ordinary bezels.
        case toolbar
        case window
    }

    let notice: TrialNotice
    var placement = Placement.toolbar

    var body: some View {
        let button = Button(AppCommand.purchase.title) { PurchaseSheet.show(on: NSApp.keyWindow) }
        switch (placement, notice.urgency.color) {
        case let (.toolbar, color?):
            button.buttonStyle(.glassProminent).tint(color)
        case (.toolbar, nil):
            button.buttonStyle(.glass)
        case let (.window, color?):
            button.buttonStyle(.borderedProminent).tint(color)
        case (.window, nil):
            button.buttonStyle(.bordered)
        }
    }
}

/// The trial's notice in the dashboard's bottom bar, since the dashboard is often the only window
/// open, and its Clone and Create are locked with the rest after the trial.
struct DashboardTrialNotice: View {
    let entitlements: EntitlementStore

    var body: some View {
        if let notice = entitlements.notice {
            HStack(spacing: 6) {
                TrialNoticeIcon(notice: notice)
                WholeWordsText(text: notice.message)
                    .foregroundStyle(.secondary)
                    .help(notice.message)
                PurchaseButton(notice: notice, placement: .window)
            }
        }
    }
}
