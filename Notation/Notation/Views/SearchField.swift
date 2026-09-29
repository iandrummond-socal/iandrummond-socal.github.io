import SwiftUI
import UIKit

/// UITextField that also reacts to hardware Up / Down / Escape, even though the field would normally swallow them.
final class KeyTextField: UITextField {
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onEscape: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        [
            command(UIKeyCommand.inputUpArrow, #selector(handleUp)),
            command(UIKeyCommand.inputDownArrow, #selector(handleDown)),
            command(UIKeyCommand.inputEscape, #selector(handleEscape)),
        ]
    }

    private func command(_ input: String, _ action: Selector) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: [], action: action)
        command.wantsPriorityOverSystemBehavior = true
        return command
    }

    @objc private func handleUp() { onUp?() }
    @objc private func handleDown() { onDown?() }
    @objc private func handleEscape() { onEscape?() }
}

/// The one field: search, select and create all start here. Dumb view: it shows `text` and reports what the user does.
struct SearchField: UIViewRepresentable {
    let text: String
    let shouldFocus: Bool
    let onEdit: (String) -> Void
    let onSubmit: () -> Void
    let onMove: (Int) -> Void
    let onEscape: () -> Void
    let onFocusHandled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> KeyTextField {
        let field = KeyTextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.font = .systemFont(ofSize: 17)
        field.textColor = Theme.uiText
        field.tintColor = Theme.uiText
        field.attributedPlaceholder = NSAttributedString(
            string: "Search or Create",
            attributes: [.foregroundColor: Theme.uiSecondary]
        )
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .go
        field.enablesReturnKeyAutomatically = false
        field.clearButtonMode = .whileEditing
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.accessibilityLabel = "Search or Create"
        return field
    }

    func updateUIView(_ field: KeyTextField, context: Context) {
        context.coordinator.parent = self
        field.onUp = { onMove(-1) }
        field.onDown = { onMove(1) }
        field.onEscape = onEscape
        if field.text != text { field.text = text }
        if shouldFocus {
            FirstResponder.grab(field) { onFocusHandled() }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SearchField?

        @objc func editingChanged(_ field: UITextField) {
            parent?.onEdit(field.text ?? "")
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent?.onSubmit()
            return false
        }

        /// Handle the clear button ourselves so "clearing restores the previous query" is one code path.
        func textFieldShouldClear(_ field: UITextField) -> Bool {
            parent?.onEdit("")
            return false
        }
    }
}

enum FirstResponder {
    /// Makes `view` first responder, retrying briefly because a just-created view may not be in a window yet.
    static func grab(_ view: UIView, attempts: Int = 8, then done: @escaping () -> Void) {
        DispatchQueue.main.async {
            if view.window != nil {
                view.becomeFirstResponder()
                done()
            } else if attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    grab(view, attempts: attempts - 1, then: done)
                }
            } else {
                done()
            }
        }
    }
}
