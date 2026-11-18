import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

struct ShortcutConfiguration: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    static let `default` = ShortcutConfiguration(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(cmdKey | shiftKey),
        key: "V"
    )

    var displayValue: String {
        var value = ""
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        return value + key
    }
}

@MainActor
final class GlobalShortcutManager: ObservableObject {
    var onShortcut: (() -> Void)?

    @Published private(set) var shortcut: ShortcutConfiguration
    @Published private(set) var errorMessage: String?

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let defaults: UserDefaults
    private let shortcutDefaultsKey = "clipshelf.globalShortcut"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: shortcutDefaultsKey),
           let savedShortcut = try? JSONDecoder().decode(ShortcutConfiguration.self, from: data),
           Self.isValid(savedShortcut) {
            shortcut = savedShortcut
        } else {
            shortcut = .default
        }
    }

    func register() {
        guard installEventHandler() else { return }
        register(shortcut, persist: false)
    }

    func setShortcut(_ newShortcut: ShortcutConfiguration) {
        guard Self.isValid(newShortcut) else {
            errorMessage = "Pilih shortcut dengan ⌘, ⌥, atau ⌃ agar tidak mudah bentrok."
            return
        }
        guard installEventHandler() else { return }
        register(newShortcut, persist: true)
    }

    func resetShortcut() {
        setShortcut(.default)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private func register(_ newShortcut: ShortcutConfiguration, persist: Bool) {
        if hotKey != nil && newShortcut.keyCode == shortcut.keyCode && newShortcut.modifiers == shortcut.modifiers {
            shortcut = newShortcut
            errorMessage = nil
            if persist { save(newShortcut) }
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x43534C46), id: 1)
        var newHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            newShortcut.keyCode,
            newShortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKey
        )

        guard status == noErr, let newHotKey else {
            errorMessage = "Shortcut \(newShortcut.displayValue) tidak bisa dipakai. Coba kombinasi lain."
            return
        }

        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = newHotKey
        shortcut = newShortcut
        errorMessage = nil
        if persist { save(newShortcut) }
    }

    private func installEventHandler() -> Bool {
        guard eventHandler == nil else { return true }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleEvent,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else {
            errorMessage = "ClipShelf tidak bisa mendaftarkan penerima shortcut."
            return false
        }
        return true
    }

    private func save(_ shortcut: ShortcutConfiguration) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: shortcutDefaultsKey)
    }

    private static func isValid(_ shortcut: ShortcutConfiguration) -> Bool {
        let requiredModifiers = UInt32(cmdKey | optionKey | controlKey)
        return shortcut.modifiers & requiredModifiers != 0 && !shortcut.key.isEmpty
    }

    private static let handleEvent: EventHandlerProcPtr = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.id == 1 else { return OSStatus(eventNotHandledErr) }

        let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
        DispatchQueue.main.async { manager.onShortcut?() }
        return noErr
    }
}
