import Foundation

/// Shorter versions of a line of text: without what's in brackets, then dropping whole sentences
/// from the end, then whole words.
nonisolated enum WholeWordShortening {
    /// The whole text first, then each shorter one. Brackets go first because the notices keep a
    /// commit's subject there, and the hash beside it is what Copy Hash copies. The ellipsis is set
    /// apart from the last word, so a hash that ends the text still reads as whole.
    static func candidates(for text: String) -> [String] {
        var candidates = [text]
        let unbracketed = text.replacing(/\s\([^()]*\)/, with: "")
        if unbracketed != text {
            candidates.append(unbracketed)
        }
        let sentences = unbracketed.components(separatedBy: ". ")
        if sentences.count > 1 {
            for count in stride(from: sentences.count - 1, through: 1, by: -1) {
                let kept = sentences.prefix(count).joined(separator: ". ")
                candidates.append(kept.hasSuffix(".") ? kept : kept + ".")
            }
        }
        let words = (sentences.first ?? unbracketed).split(separator: " ")
        if words.count > 1 {
            for count in stride(from: words.count - 1, through: 1, by: -1) {
                candidates.append(words.prefix(count).joined(separator: " ") + " …")
            }
        }
        return candidates
    }
}
