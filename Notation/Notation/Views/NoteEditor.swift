import SwiftUI
import UIKit

final class KeyTextView: UITextView {
    var onEscape: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscape))
        escape.wantsPriorityOverSystemBehavior = true
        return [escape]
    }

    @objc private func handleEscape() { onEscape?() }
}

/// Plain-text editor for the open note: system text face, no toolbar, no formatting. Dumb view.
struct NoteEditor: UIViewRepresentable {
    let text: String
    let fontSize: Double
    let shouldFocus: Bool
    let onChange: (String) -> Void
    let onEscape: () -> Void
    let onFocusHandled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> KeyTextView {
        let view = KeyTextView()
        view.delegate = context.coordinator
        view.backgroundColor = Theme.uiField
        view.textColor = Theme.uiText
        view.tintColor = Theme.uiText
        view.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.autocapitalizationType = .sentences
        view.accessibilityLabel = "Note"
        apply(text: text, to: view, coordinator: context.coordinator, force: true)
        return view
    }

    func updateUIView(_ view: KeyTextView, context: Context) {
        context.coordinator.parent = self
        view.onEscape = onEscape
        apply(text: text, to: view, coordinator: context.coordinator, force: false)
        if shouldFocus {
            FirstResponder.grab(view) { onFocusHandled() }
        }
    }

    private func apply(text: String, to view: KeyTextView, coordinator: Coordinator, force: Bool) {
        let attributes = Self.attributes(size: fontSize)
        let fontChanged = coordinator.appliedFontSize != fontSize
        if force || view.text != text {
            view.attributedText = NSAttributedString(string: text, attributes: attributes)
        } else if fontChanged {
            view.textStorage.setAttributes(attributes, range: NSRange(location: 0, length: view.textStorage.length))
        }
        view.typingAttributes = attributes
        coordinator.appliedFontSize = fontSize
    }

    /// 17pt system text at 1.35 line height by default.
    static func attributes(size: Double) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = Theme.bodyLineHeightMultiple
        return [
            .font: UIFont.systemFont(ofSize: CGFloat(size)),
            .foregroundColor: Theme.uiText,
            .paragraphStyle: style,
        ]
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteEditor?
        var appliedFontSize: Double = 0

        func textViewDidChange(_ textView: UITextView) {
            parent?.onChange(textView.text ?? "")
        }
    }
}
