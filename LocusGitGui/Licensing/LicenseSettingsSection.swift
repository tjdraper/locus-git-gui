import SwiftUI

/// How long the trial has left, or that it has ended and what that means.
struct LicenseSettingsSection: View {
    let entitlements: EntitlementStore

    var body: some View {
        Section {
            LabeledContent("Trial") {
                Text(status)
            }
            if let trialStart = entitlements.trialStart, let end = entitlements.entitlement.until {
                LabeledContent("Started", value: trialStart.formatted(date: .long, time: .omitted))
                LabeledContent(entitlements.isEntitled ? "Ends" : "Ended", value: end.formatted(date: .long, time: .shortened))
            }
            if let notice = entitlements.notice {
                HStack {
                    Spacer()
                    PurchaseButton(notice: notice, placement: .window)
                }
            }
        } footer: {
            Text(footer)
                .foregroundStyle(.secondary)
        }
    }

    private var status: String {
        if entitlements.entitlement.reason == .checking {
            return "Checking…"
        }
        guard entitlements.isEntitled else { return "Ended" }
        return switch entitlements.trialDaysLeft {
        case 1: "1 day left"
        case let daysLeft?: "\(daysLeft) days left"
        case nil: "Active"
        }
    }

    private var footer: String {
        if entitlements.isEntitled {
            """
            Everything works during the 30-day trial. It started the first time Locus Git Gui \
            opened, on this Mac or another signed in to the same Apple ID.
            """
        } else {
            """
            Locus Git Gui still opens your repositories and shows their history, changes, and \
            status. Changing a repository or talking to a remote needs a license.
            """
        }
    }
}
