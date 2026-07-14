import SwiftUI
#if canImport(UIKit)
import UIKit

/// The capture input, backed by a UITextView so we can add capture actions ("record voice", later
/// "add photo") to the text field's own edit menu — the same way the article transcript adds
/// "filament" / "make to-do" (see SelectableTextView). Placeholder and focus are driven from
/// SwiftUI; the field auto-grows with its content (no internal scrolling).
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var onRecordVoice: () -> Void
    var onAddPhoto: () -> Void

    /// Matches Theme.dmSans(20, .medium): the system body font scaled to 20pt so it tracks Dynamic Type.
    static var font: UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 20, weight: .medium))
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.font = Self.font
        tv.textColor = UIColor(Theme.primaryText)
        tv.tintColor = UIColor(Theme.primaryText)
        tv.adjustsFontForContentSizeCategory = true
        tv.delegate = context.coordinator
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text { tv.text = text }
        tv.font = Self.font

        // Bridge SwiftUI focus <-> first responder (deferred so we don't mutate during a view update).
        if isFocused, !tv.isFirstResponder {
            DispatchQueue.main.async { tv.becomeFirstResponder() }
        } else if !isFocused, tv.isFirstResponder {
            DispatchQueue.main.async { tv.resignFirstResponder() }
        }
    }

    /// Constrain the text view to the width SwiftUI proposes so it wraps (and grows in height)
    /// instead of running off to the right. Without this, a scroll-disabled UITextView reports its
    /// single-line intrinsic width and the text never line-breaks.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width < .infinity else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitted.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView
        init(parent: ComposerTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }

        /// Add "record voice" to the field's edit menu (both the caret menu and the selection menu),
        /// alongside the system items (paste, autofill, …).
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            let record = UIAction(title: "record voice", image: UIImage(systemName: "mic.fill")) { [weak self] _ in
                self?.parent.onRecordVoice()
            }
            let photo = UIAction(title: "add photo", image: UIImage(systemName: "photo")) { [weak self] _ in
                self?.parent.onAddPhoto()
            }
            return UIMenu(children: [record, photo] + suggestedActions)
        }
    }
}
#endif
