import SwiftUI
import UIKit

/// Switch Today's blocks on/off, drag to reorder, and keep the screen awake.
struct TodayCustomiseView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        let order: [TodayModule] = {
            var o = store.settings.todayOrder.compactMap(TodayModule.init(rawValue:))
            for m in TodayModule.allCases where !o.contains(m) { o.append(m) }
            return o
        }()
        List {
            Section {
                ForEach(order) { m in
                    Toggle(isOn: Binding(
                        get: { !store.settings.todayHidden.contains(m.rawValue) },
                        set: { on in
                            store.settings.todayHidden.removeAll { $0 == m.rawValue }
                            if !on { store.settings.todayHidden.append(m.rawValue) }
                        })) {
                        Label(m.title, systemImage: m.symbol)
                    }
                }
                .onMove { from, to in
                    var o = order
                    o.move(fromOffsets: from, toOffset: to)
                    store.settings.todayOrder = o.map(\.rawValue)
                }
            } header: {
                Text("Today screen")
            } footer: {
                Text("Switch blocks on or off. Drag the ≡ handles to change the order. Today's job, vehicle and mileage only show while you're on a shift.")
            }
            Section {
                Picker("Keep the screen on", selection: Binding(get: { store.settings.keepScreenOn }, set: { store.settings.keepScreenOn = $0 })) {
                    Text("While on a shift").tag("shift")
                    Text("Always (app open)").tag("always")
                    Text("Never").tag("never")
                }
            } footer: {
                Text("Stops the iPhone dimming and locking while HGV Hours is open. Uses more battery — keep the phone on charge in the cab.")
            }
            Section {
                Button("Reset to default layout") {
                    store.settings.todayOrder = TodayModule.allCases.map(\.rawValue)
                    store.settings.todayHidden = []
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Customise Today")
    }
}

enum ScreenAwake {
    /// Applies the keep-screen-on setting.
    @MainActor
    static func apply(_ settings: AppSettings, onShift: Bool) {
        let on: Bool
        switch settings.keepScreenOn {
        case "always": on = true
        case "shift": on = onShift
        default: on = false
        }
        UIApplication.shared.isIdleTimerDisabled = on
    }
}
