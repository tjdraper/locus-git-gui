import Foundation

/// Leaving comments on the review, its files and their lines, replying to them, and resolving them.
extension ReviewSession {
    @discardableResult
    func startThread(_ place: ReviewThread.Place, body: String) -> UUID {
        let thread = ReviewThread(id: UUID(), place: place, comments: [comment(body)])
        store.update(id, in: repository) { review in
            review.threads.append(thread)
            review.lastChanged = Date()
        }
        Task { await keepObjects() }
        return thread.id
    }

    func reply(to thread: UUID, body: String) {
        changeThread(thread) { $0.comments.append(comment(body)) }
    }

    func edit(_ comment: UUID, in thread: UUID, body: String) {
        changeThread(thread) { thread in
            guard let index = thread.comments.firstIndex(where: { $0.id == comment }) else { return }
            thread.comments[index].body = body
            thread.comments[index].edited = Date()
        }
    }

    /// The thread goes with its last comment.
    func delete(_ comment: UUID, in thread: UUID) {
        store.update(id, in: repository) { review in
            guard let index = review.threads.firstIndex(where: { $0.id == thread }) else { return }
            review.threads[index].comments.removeAll { $0.id == comment }
            if review.threads[index].comments.isEmpty {
                review.threads.remove(at: index)
            }
            review.lastChanged = Date()
        }
    }

    func setResolved(_ thread: UUID, _ isResolved: Bool) {
        changeThread(thread) { $0.resolved = isResolved ? Date() : nil }
    }

    private func changeThread(_ id: UUID, _ change: (inout ReviewThread) -> Void) {
        store.update(self.id, in: repository) { review in
            guard let index = review.threads.firstIndex(where: { $0.id == id }) else { return }
            change(&review.threads[index])
            review.lastChanged = Date()
        }
    }

    private func comment(_ body: String) -> ReviewComment {
        ReviewComment(id: UUID(), body: body, created: Date())
    }
}
