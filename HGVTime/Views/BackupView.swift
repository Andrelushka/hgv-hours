import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Back up everything to a file, or restore from one.
struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @State private var backupURL: URL?
    @State private var importing = false
    @State private var pending: BackupService.Backup?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Button {
                    do {
                        backupURL = try BackupService.export(context: context, settings: store.settings)
                        message = nil
                    } catch {
                        message = "Couldn't create the backup: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Create backup", systemImage: "externaldrive.badge.plus")
                }
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label("Save or send \(backupURL.lastPathComponent)", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Back up")
            } footer: {
                Text("One file with all your shifts, plans, vehicles, notes, pay items, events, routes, reminders and settings. Save it to Files or iCloud Drive, AirDrop it, or email it to yourself. Keep it private — it holds your work records.")
            }

            Section {
                Button(role: .destructive) { importing = true } label: {
                    Label("Restore from a backup file", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Restore")
            } footer: {
                Text("Restoring replaces everything on this iPhone with the backup. Make a backup of this phone first if you might need it.")
            }

            if let message {
                Section { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("Backup & restore")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item, .json]) { result in
            switch result {
            case .success(let url):
                do { pending = try BackupService.read(url) } catch { message = "That file isn't an HGV Hours backup." }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .confirmationDialog("Replace everything with this backup?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { b in
            Button("Restore backup", role: .destructive) {
                do {
                    try BackupService.restore(b, context: context, store: store)
                    message = "Restored \(b.entries.count) activities, \(b.plans.count) plans and \(b.vehicles.count) vehicles from \(Fmt.dayTime(b.createdAt))."
                } catch {
                    message = "Restore failed: \(error.localizedDescription)"
                }
            }
        } message: { b in
            Text("Backup from \(Fmt.dayTime(b.createdAt)) (app \(b.appVersion)): \(b.entries.count) activities, \(b.plans.count) plans, \(b.vehicles.count) vehicles, \(b.notes.count) notes. Everything currently on this iPhone will be replaced. This can't be undone.")
        }
    }
}
