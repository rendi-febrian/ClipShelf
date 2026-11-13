import AppKit
import Combine
import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String?
    let imageData: Data?
    let copiedAt: Date
    let sourceApp: String

    var isImage: Bool { imageData != nil }

    var preview: String {
        if isImage { return "Image" }
        return text ?? ""
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var isPaused = false
    @Published var notice: String?

    private let maximumItems = 80
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let excludedBundleIdentifiers: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.apple.keychainaccess"
    ]

    init() {
        loadHistory()
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captureClipboardChange()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func togglePause() {
        isPaused.toggle()
        if !isPaused {
            lastChangeCount = NSPasteboard.general.changeCount
        }
    }

    func clearHistory() {
        items.removeAll()
        saveHistory()
    }

    func filteredItems(matching query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        return items.filter { $0.preview.localizedCaseInsensitiveContains(query) }
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let text = item.text {
            pasteboard.setString(text, forType: .string)
        } else if let imageData = item.imageData {
            pasteboard.setData(imageData, forType: .png)
        }
        lastChangeCount = pasteboard.changeCount
    }

    private func captureClipboardChange() {
        guard !isPaused else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let source = NSWorkspace.shared.frontmostApplication
        if let bundleIdentifier = source?.bundleIdentifier,
           excludedBundleIdentifiers.contains(bundleIdentifier) {
            return
        }

        let newItem: ClipboardItem?
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           text.utf8.count <= 500_000 {
            newItem = ClipboardItem(
                id: UUID(), text: text, imageData: nil, copiedAt: Date(),
                sourceApp: source?.localizedName ?? "Unknown app"
            )
        } else if let imageData = imagePNGData(from: pasteboard), imageData.count <= 4_000_000 {
            newItem = ClipboardItem(
                id: UUID(), text: nil, imageData: imageData, copiedAt: Date(),
                sourceApp: source?.localizedName ?? "Unknown app"
            )
        } else {
            newItem = nil
        }

        guard let newItem else { return }
        if let latest = items.first, latest.text == newItem.text, latest.imageData == newItem.imageData {
            return
        }
        items.insert(newItem, at: 0)
        if items.count > maximumItems {
            items = Array(items.prefix(maximumItems))
        }
        saveHistory()
    }

    private func imagePNGData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff),
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private var historyURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("history.json")
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        items = Array(decoded.prefix(maximumItems))
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }
}

