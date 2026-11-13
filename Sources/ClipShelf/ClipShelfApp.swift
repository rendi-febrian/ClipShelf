import AppKit
import SwiftUI

@main
struct ClipShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ClipboardStore()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var shortcutManager: GlobalShortcutManager?
    private var lastExternalApplication: NSRunningApplication?
    private var targetApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        lastExternalApplication = NSWorkspace.shared.frontmostApplication
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipShelf")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 370, height: 510)
        popover.contentViewController = NSHostingController(
            rootView: ClipboardPanel(store: store, onSelect: { [weak self] item in
                self?.select(item)
            })
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        let manager = GlobalShortcutManager()
        manager.onShortcut = { [weak self] in
            self?.togglePopover()
        }
        manager.register()
        shortcutManager = manager
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastExternalApplication = application
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        targetApplication = lastExternalApplication ?? NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func select(_ item: ClipboardItem) {
        store.copyToPasteboard(item)

        guard CGPreflightPostEventAccess() else {
            store.notice = "Sudah disalin. Aktifkan auto-paste di Pengaturan, atau tutup panel lalu tekan ⌘V."
            return
        }

        store.notice = nil
        popover.performClose(nil)

        guard let targetApplication, !targetApplication.isTerminated else { return }
        targetApplication.activate(options: [.activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Self.postCommandV()
        }
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

