import LocalAuthentication
import SwiftUI

/// Face ID / Touch ID / passcode check.
enum AppLock {
    static var biometryName: String {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch c.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "your passcode"
        }
    }

    static var isAvailable: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    /// Falls back to the phone passcode if Face ID fails.
    static func authenticate(reason: String = "Unlock HGV Hours") async -> Bool {
        let c = LAContext()
        c.localizedCancelTitle = "Cancel"
        return (try? await c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Covers the app until you unlock it.
struct LockScreenView: View {
    var unlock: () -> Void
    @State private var failed = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "truck.box.fill")
                .font(.system(size: 54))
                .foregroundStyle(.white)
                .frame(width: 100, height: 100)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 24))
            Text("HGV Hours is locked").font(.title2.weight(.bold))
            if failed { Text("Couldn't unlock. Try again.").foregroundStyle(.secondary) }
            Button {
                Task { await attempt() }
            } label: {
                Label("Unlock with \(AppLock.biometryName)", systemImage: "faceid")
                    .font(.headline).frame(maxWidth: 280).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task { await attempt() }
    }

    private func attempt() async {
        if await AppLock.authenticate() {
            unlock()
        } else {
            failed = true
        }
    }
}

/// Settings for the app lock.
struct LockSettingsView: View {
    @Environment(SettingsStore.self) private var store
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("Lock with \(AppLock.biometryName)", isOn: Binding(
                    get: { store.settings.lockEnabled },
                    set: { on in
                        Task {
                            // Confirm it's you before changing the lock.
                            if await AppLock.authenticate(reason: on ? "Turn on the app lock" : "Turn off the app lock") {
                                store.settings.lockEnabled = on
                            } else {
                                error = "Couldn't confirm it's you."
                            }
                        }
                    }))
                .disabled(!AppLock.isAvailable)
                if store.settings.lockEnabled {
                    Picker("Lock again after", selection: Binding(get: { store.settings.lockAfterMinutes }, set: { store.settings.lockAfterMinutes = $0 })) {
                        Text("Immediately").tag(0)
                        Text("1 minute").tag(1)
                        Text("5 minutes").tag(5)
                        Text("15 minutes").tag(15)
                        Text("1 hour").tag(60)
                    }
                }
            } footer: {
                if !AppLock.isAvailable {
                    Text("Set up a passcode on this iPhone to use the app lock.")
                } else {
                    Text(error ?? "Asks for \(AppLock.biometryName) (or your iPhone passcode) when you open HGV Hours. Widgets, the Lock Screen countdown and the Watch still show your hours.")
                }
            }
        }
        .navigationTitle("App lock")
    }
}
