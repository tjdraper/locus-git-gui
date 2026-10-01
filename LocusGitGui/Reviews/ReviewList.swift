import Foundation

/// A repository's reviews as the toolbar's popover and the Reviews window list them, and what can
/// be done with each.
@Observable
final class ReviewList {
    let repository: Repository
    @ObservationIgnored private let store: ReviewStore
    var showsOlder = false {
        didSet {
            if showsOlder != oldValue {
                onChange?()
            }
        }
    }

    @ObservationIgnored var onOpen: ((UUID) -> Void)?
    @ObservationIgnored var onNewReview: (() -> Void)?
    @ObservationIgnored var onRename: ((UUID) -> Void)?
    @ObservationIgnored var onDelete: ((UUID) -> Void)?
    /// Show Older Reviews, for the repository to remember.
    @ObservationIgnored var onChange: (() -> Void)?

    init(repository: Repository, store: ReviewStore) {
        self.repository = repository
        self.store = store
    }

    var reviews: [Review] {
        ReviewListing.shown(store.reviews(in: repository), at: Date(), includingOlder: showsOlder)
    }

    var olderCount: Int {
        ReviewListing.olderCount(store.reviews(in: repository), at: Date())
    }

    var isEmpty: Bool {
        store.reviews(in: repository).isEmpty
    }
}
