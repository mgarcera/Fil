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

        /// Build the field's edit menu: paste first (only when there's something to paste), then our
        /// capture actions, then the remaining system items. Our custom paste replaces the system's
        /// one — which we strip below — so it isn't duplicated when it leads.
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            let record = UIAction(title: "Record voice", image: UIImage(systemName: "mic.fill")) { [weak self] _ in
                self?.parent.onRecordVoice()
            }
            let photo = UIAction(title: "Add photo", image: UIImage(systemName: "photo")) { [weak self] _ in
                self?.parent.onAddPhoto()
            }

            var leading: [UIMenuElement] = []
            let pasteboard = UIPasteboard.general
            if pasteboard.hasStrings || pasteboard.hasURLs {
                leading.append(UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { _ in
                    textView.paste(nil)
                })
            }
            leading.append(contentsOf: [record, photo])

            // Drop the system's own paste so ours (above) isn't duplicated; keep everything else.
            let remaining = suggestedActions.compactMap(Self.strippingPaste)
            return UIMenu(children: leading + remaining)
        }

        /// Recursively removes a "paste" command from a menu element (English-only title match; the
        /// app ships in English today). Returns nil if the element itself is the paste action.
        private static func strippingPaste(_ element: UIMenuElement) -> UIMenuElement? {
            if let menu = element as? UIMenu {
                return menu.replacingChildren(menu.children.compactMap(strippingPaste))
            }
            if element.title.lowercased() == "paste" { return nil }
            return element
        }
    }
}
#endif
