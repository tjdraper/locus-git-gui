import SwiftUI

/// Text on one line that, when it doesn't fit, drops whole sentences from the end and then whole
/// words, rather than cut a word short. A commit hash cut short reads as a different, real hash.
struct WholeWordsText: View {
    let text: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(WholeWordShortening.candidates(for: text), id: \.self) { candidate in
                Text(candidate)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text("")
        }
    }
}
