import AppKit
import SwiftUI

struct ClipboardPanel: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var shortcutManager: GlobalShortcutManager
    let onSelect: (ClipboardItem) -> Void

    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var pendingShareItem: ClipboardItem?
    @State private var activeShareItemID: UUID?
    @State private var isShowingShareConfirmation = false
    @State private var shareAlert: ShareAlert?

    private var visibleItems: [ClipboardItem] {
        store.filteredItems(matching: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider().padding(.vertical, 10)
            if let notice = store.notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 8)
            }

            if visibleItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleItems) { item in
                            itemRow(item)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.automatic)
            }

            Divider().padding(.vertical, 10)
            footer
        }
        .padding(14)
        .frame(width: 370, height: 510)
        .background(.regularMaterial)
        .onAppear { searchFocused = true }
        .confirmationDialog(
            "Bagikan clipboard sebagai link?",
            isPresented: $isShowingShareConfirmation,
            titleVisibility: .visible
        ) {
            Button("Buat link") {
                guard let item = pendingShareItem else { return }
                Task { await createShare(for: item) }
            }
            Button("Batal", role: .cancel) {
                pendingShareItem = nil
            }
        } message: {
            Text("Teks akan dikirim ke clipshelf.ild.my.id dan bisa dibaca siapa saja yang memiliki link selama 7 hari. Jangan bagikan kata sandi atau data sensitif.")
        }
        .alert(item: $shareAlert) { alert in
            if let url = alert.url {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .default(Text("Salin link")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    },
                    secondaryButton: .cancel(Text("Tutup"))
                )
            }
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Clipboard")
                    .font(.system(size: 16, weight: .semibold))
                Text("Disimpan lokal di Mac ini")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(shortcutManager.shortcut.displayValue)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Cari clipboard…", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(.system(size: 13))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary, lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 25))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "Belum ada riwayat" : "Tidak ada hasil")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if searchText.isEmpty {
                Text("Salin teks atau gambar, lalu buka lagi dengan \(shortcutManager.shortcut.displayValue).")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    private func itemRow(_ item: ClipboardItem) -> some View {
        HStack(spacing: 8) {
            Button {
                onSelect(item)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    if let imageData = item.imageData, let image = NSImage(data: imageData) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.preview)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .lineLimit(item.isImage ? 1 : 3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 5) {
                            Text(item.sourceApp)
                            Text("·")
                            Text(item.copiedAt.formatted(date: .omitted, time: .shortened))
                            if item.isImage {
                                Text("· Gambar")
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    }
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Pilih dan tempel item ini")

            if !item.isImage, item.text != nil {
                Button {
                    pendingShareItem = item
                    isShowingShareConfirmation = true
                } label: {
                    if activeShareItemID == item.id {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 28)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(activeShareItemID != nil)
                .help("Bagikan teks sebagai link")
                .accessibilityLabel("Bagikan teks sebagai link")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary.opacity(0.75), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    @MainActor
    private func createShare(for item: ClipboardItem) async {
        guard let text = item.text else { return }
        activeShareItemID = item.id
        defer {
            activeShareItemID = nil
            pendingShareItem = nil
        }

        do {
            let url = try await ClipShelfShareClient.createLink(for: text)
            shareAlert = ShareAlert(
                title: "Link berhasil dibuat",
                message: url.absoluteString,
                url: url
            )
        } catch {
            shareAlert = ShareAlert(
                title: "Gagal membuat link",
                message: (error as? LocalizedError)?.errorDescription ?? "Terjadi kesalahan. Coba lagi nanti."
            )
        }
    }

    private struct ShareAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        var url: URL?
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                store.togglePause()
            } label: {
                Label(store.isPaused ? "Lanjutkan" : "Jeda", systemImage: store.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Pengaturan")

            Button("Hapus") {
                store.clearHistory()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .disabled(store.items.isEmpty)

            Button("Keluar") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .help("Keluar dari ClipShelf")
        }
        .foregroundStyle(.secondary)
    }
}

