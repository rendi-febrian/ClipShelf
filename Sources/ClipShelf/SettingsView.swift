import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ClipboardStore
    @StateObject private var loginItemManager = LoginItemManager()
    @State private var permissionStatus = CGPreflightPostEventAccess()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Buka riwayat", value: "⌘⇧V")
                Text("Shortcut ini dapat mengambil alih fungsi ⌘⇧V di app lain, misalnya tempel tanpa format di Google Docs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Saat login") {
                Toggle("Jalankan ClipShelf saat saya login", isOn: Binding(
                    get: { loginItemManager.isRegistered },
                    set: { loginItemManager.setEnabled($0) }
                ))
                Text("ClipShelf akan berjalan di menu bar setiap kali kamu masuk ke akun Mac ini.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if loginItemManager.needsApproval {
                    Text("ClipShelf sudah terdaftar, tapi macOS masih perlu persetujuan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Buka Pengaturan Login Items") {
                        loginItemManager.openLoginItemsSettings()
                    }
                }

                if let errorMessage = loginItemManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Auto-paste") {
                Text("Memilih item akan mengaktifkannya di app sebelumnya dan mengirim ⌘V. Beri izin di sini; tanpa izin, item hanya disalin dan kamu bisa menempelkannya dengan ⌘V.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(permissionStatus ? "Izin auto-paste aktif" : "Aktifkan auto-paste") {
                    permissionStatus = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
                }
                .disabled(permissionStatus)
                if !permissionStatus {
                    Text("Kalau macOS membuka Pengaturan Sistem, izinkan ClipShelf mengirim input keyboard, lalu coba lagi.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Privasi") {
                Text("Riwayat disimpan sebagai file lokal di akun Mac ini, tanpa sinkronisasi atau enkripsi tambahan. Clipboard dari 1Password, Bitwarden, KeePassXC, dan Keychain Access diabaikan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Jeda pemantauan clipboard", isOn: Binding(
                    get: { store.isPaused },
                    set: { _ in store.togglePause() }
                ))
                Button("Hapus semua riwayat", role: .destructive) {
                    store.clearHistory()
                }
            }

            Section("Tentang") {
                LabeledContent("Versi", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Riwayat tersimpan", value: "\(store.items.count) item")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding(.vertical, 8)
        .onAppear {
            permissionStatus = CGPreflightPostEventAccess()
            loginItemManager.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                loginItemManager.refresh()
            }
        }
    }
}

