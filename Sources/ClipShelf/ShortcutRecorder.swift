import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let isRecording: Bool
    let onRecord: (ShortcutConfiguration) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureView {
        let view = ShortcutCaptureView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        view.isRecording = isRecording
        return view
    }

    func updateNSView(_ view: ShortcutCaptureView, context: Context) {
        view.onRecord = onRecord
        view.onCancel = onCancel
        view.isRecording = isRecording
    }
}

final class ShortcutCaptureView: NSView {
    var onRecord: ((ShortcutConfiguration) -> Void)?
    var onCancel: (() -> Void)?
    private weak var previousFirstResponder: NSResponder?
    var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            if isRecording {
                focusIfRecording()
            } else {
                restoreFocus()
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }

        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        let requiredModifiers = UInt32(cmdKey | optionKey | controlKey)
        guard modifiers & requiredModifiers != 0 else {
            NSSound.beep()
            return
        }

        guard let key = Self.keyName(for: event), !key.isEmpty else {
            NSSound.beep()
            return
        }

        onRecord?(ShortcutConfiguration(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            key: key
        ))
    }

    private func focusIfRecording() {
        guard isRecording else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRecording else { return }
            guard let window = self.window else { return }
            if window.firstResponder !== self {
                self.previousFirstResponder = window.firstResponder
                window.makeFirstResponder(self)
            }
        }
    }

    private func restoreFocus() {
        let responder = previousFirstResponder
        previousFirstResponder = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(responder)
        }
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private static func keyName(for event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Return, kVK_ANSI_KeypadEnter: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            return event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
    }
}
