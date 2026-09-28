import AppKit

/// How diffs are drawn, as Settings has it: the font and the measurements that follow from it, and
/// whether they're side by side.
struct DiffAppearance {
    let font: NSFont
    let layout: DiffPreferences.Layout
    let metrics: DiffLayout.Metrics
    let painter: DiffRowPainter

    init(preferences: DiffPreferences = DiffPreferences()) {
        font = preferences.font
        layout = preferences.layout
        let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
        let fontHeight = font.ascender - font.descender + font.leading
        metrics = DiffLayout.Metrics(advance: advance, lineHeight: (fontHeight + 5).rounded(.up))
        painter = DiffRowPainter(font: font, metrics: metrics)
    }

    func differs(from other: DiffAppearance) -> Bool {
        font != other.font || layout != other.layout
    }
}
