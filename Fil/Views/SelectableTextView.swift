import SwiftUI
#if canImport(UIKit)
import UIKit

struct SelectableTextView: UIViewRepresentable {
    let text: String
    let highlightedKeywords: [String]
    let gradientStartHex: String
    let gradientEndHex: String
    var onSelectText: (String, CGRect) -> Void
    var onTapHighlight: ((String) -> Void)?
    var onMakeTodo: ((String) -> Void)?
    @Binding var height: CGFloat
    /// Body text color; defaults to adaptive `.label`. The player passes white for its dark wash.
    var textColor: UIColor? = nil

    private var lighterHex: String {
        let startLuminance = Color(hex: gradientStartHex).luminance
        let endLuminance = Color(hex: gradientEndHex).luminance
        return endLuminance > startLuminance ? gradientEndHex : gradientStartHex
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.label
        ]
        return textView
    }

    /// Body-relative Dynamic Type fonts so the selectable transcript scales like the rest of the app.
    /// Fredoka (matching the fil card), with a system fallback if the bundled font isn't registered.
    private var bodyFont: UIFont {
        let base = UIFont(name: "Fredoka-Regular", size: 16) ?? .systemFont(ofSize: 16)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
    }
    private var boldBodyFont: UIFont {
        let base = UIFont(name: "Fredoka-Medium", size: 16) ?? .boldSystemFont(ofSize: 16)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self

        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: bodyFont,
            .foregroundColor: textColor ?? UIColor.label.withAlphaComponent(0.85),
            .paragraphStyle: {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 6
                return style
            }()
        ])

        let highlightColor = UIColor(Color(hex: lighterHex))
        for keyword in highlightedKeywords {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: keyword, options: .caseInsensitive, range: searchRange) {
                let nsRange = NSRange(range, in: text)
                let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? keyword
                if let url = URL(string: "fil-highlight://\(encoded)") {
                    attributed.addAttributes([
                        .font: boldBodyFont,
                        .foregroundColor: highlightColor,
                        .link: url
                    ], range: nsRange)
                }
                searchRange = range.upperBound..<text.endIndex
            }
        }

        textView.linkTextAttributes = [
            .foregroundColor: UIColor(Color(hex: lighterHex)),
            .font: boldBodyFont
        ]
        textView.attributedText = attributed

        DispatchQueue.main.async {
            let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
            if size.height != height && textView.bounds.width > 0 {
                height = size.height
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableTextView

        init(parent: SelectableTextView) {
            self.parent = parent
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            if case .link(let url) = textItem.content,
               url.scheme == "fil-highlight",
               let keyword = url.host(percentEncoded: false) {
                return UIAction { [weak self] _ in
                    self?.parent.onTapHighlight?(keyword)
                }
            }
            return defaultAction
        }

        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            if case .link = textItem.content {
                return nil
            }
            return UITextItem.MenuConfiguration(menu: defaultMenu)
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0 else { return UIMenu(children: suggestedActions) }

            let attachAction = UIAction(title: "Filament", image: UIImage(systemName: "paperclip")) { [weak self] _ in
                guard let self else { return }
                let nsText = textView.text as NSString
                let selectedText = nsText.substring(with: range)
                guard !selectedText.isEmpty else { return }

                let start = textView.position(from: textView.beginningOfDocument, offset: range.location)
                let end = textView.position(from: textView.beginningOfDocument, offset: range.location + range.length)
                if let start, let end, let textRange = textView.textRange(from: start, to: end) {
                    let rect = textView.firstRect(for: textRange)
                    self.parent.onSelectText(selectedText, rect)
                }

                textView.selectedTextRange = nil
            }

            let todoAction = UIAction(title: "Add to-do", image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
                guard let self else { return }
                let selectedText = (textView.text as NSString).substring(with: range)
                guard !selectedText.isEmpty else { return }
                self.parent.onMakeTodo?(selectedText)
                textView.selectedTextRange = nil
            }

            return UIMenu(children: [attachAction, todoAction] + suggestedActions)
        }
    }
}
#elseif canImport(AppKit)
import AppKit

struct SelectableTextView: NSViewRepresentable {
    let text: String
    let highlightedKeywords: [String]
    let gradientStartHex: String
    let gradientEndHex: String
    var onSelectText: (String, CGRect) -> Void
    var onTapHighlight: ((String) -> Void)?
    var onMakeTodo: ((String) -> Void)?
    @Binding var height: CGFloat
    /// Body text color; defaults to adaptive `.label`. The player passes white for its dark wash.
    var textColor: UIColor? = nil

    private var lighterHex: String {
        let startLuminance = Color(hex: gradientStartHex).luminance
        let endLuminance = Color(hex: gradientEndHex).luminance
        return endLuminance > startLuminance ? gradientEndHex : gradientStartHex
    }

    func makeNSView(context: Context) -> FilSelectableNSTextView {
        let textView = FilSelectableNSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.parentProvider = { context.coordinator.parent }
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.labelColor
        ]
        return textView
    }

    func updateNSView(_ textView: FilSelectableNSTextView, context: Context) {
        context.coordinator.parent = self

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6

        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.85),
            .paragraphStyle: paragraphStyle
        ])

        let highlightColor = NSColor(Color(hex: lighterHex))
        for keyword in highlightedKeywords {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: keyword, options: .caseInsensitive, range: searchRange) {
                let nsRange = NSRange(range, in: text)
                let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? keyword
                if let url = URL(string: "fil-highlight://\(encoded)") {
                    attributed.addAttributes([
                        .font: NSFont.boldSystemFont(ofSize: 16),
                        .foregroundColor: highlightColor,
                        .link: url
                    ], range: nsRange)
                }
                searchRange = range.upperBound..<text.endIndex
            }
        }

        textView.linkTextAttributes = [
            .foregroundColor: highlightColor,
            .font: NSFont.boldSystemFont(ofSize: 16)
        ]
        textView.textStorage?.setAttributedString(attributed)

        DispatchQueue.main.async {
            guard textView.bounds.width > 0,
                  let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }

            textContainer.containerSize = CGSize(
                width: textView.bounds.width,
                height: .greatestFiniteMagnitude
            )
            layoutManager.ensureLayout(for: textContainer)
            let size = layoutManager.usedRect(for: textContainer).size
            if size.height != height {
                height = ceil(size.height)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableTextView

        init(parent: SelectableTextView) {
            self.parent = parent
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL,
                  url.scheme == "fil-highlight",
                  let keyword = url.host(percentEncoded: false) else {
                return false
            }

            parent.onTapHighlight?(keyword)
            return true
        }
    }
}

final class FilSelectableNSTextView: NSTextView {
    var parentProvider: (() -> SelectableTextView)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let parent = parentProvider?(),
              selectedRange().length > 0,
              let selectedText = string.nsStringSafeSubstring(with: selectedRange()),
              !selectedText.isEmpty else {
            return menu
        }

        menu.insertItem(
            withTitle: "filament",
            action: #selector(attachSelectedText(_:)),
            keyEquivalent: "",
            at: 0
        )
        menu.item(at: 0)?.target = self
        menu.insertItem(
            withTitle: "add to do",
            action: #selector(makeTodoFromSelection(_:)),
            keyEquivalent: "",
            at: 1
        )
        menu.item(at: 1)?.target = self
        representedParent = parent
        return menu
    }

    private var representedParent: SelectableTextView?

    @objc private func makeTodoFromSelection(_ sender: Any?) {
        guard let parent = representedParent,
              selectedRange().length > 0,
              let selectedText = string.nsStringSafeSubstring(with: selectedRange()) else { return }
        parent.onMakeTodo?(selectedText)
        setSelectedRange(NSRange(location: 0, length: 0))
    }

    @objc private func attachSelectedText(_ sender: Any?) {
        guard let parent = representedParent,
              selectedRange().length > 0,
              let selectedText = string.nsStringSafeSubstring(with: selectedRange()),
              let layoutManager,
              let textContainer else { return }

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: selectedRange(),
            actualCharacterRange: nil
        )
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        parent.onSelectText(selectedText, rect)
        setSelectedRange(NSRange(location: 0, length: 0))
    }
}

private extension String {
    func nsStringSafeSubstring(with range: NSRange) -> String? {
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0,
              range.location + range.length <= (self as NSString).length else {
            return nil
        }

        return (self as NSString).substring(with: range)
    }
}
#endif
