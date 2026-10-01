import SwiftUI

/// In place of a review once the trial has ended.
struct ReviewLockedView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Reviews need a license", systemImage: "lock.fill")
        } description: {
            Text("Your reviews are kept, and open again once Locus Git Gui is licensed.")
        } actions: {
            Button(AppCommand.purchase.title) {
                PurchaseSheet.show(on: NSApp.keyWindow)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
