import SwiftUI
import SwiftData

@main
struct HGVTimeApp: App {
    @State private var settingsStore = SettingsStore()
    private let container = StoreSetup.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settingsStore)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "play.circle") }
            HoursView()
                .tabItem { Label("Hours", systemImage: "gauge.with.dots.needle.67percent") }
            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet.rectangle") }
            CalendarTab()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            NotebookView()
                .tabItem { Label("Notebook", systemImage: "note.text") }
        }
        .sheet(isPresented: .constant(!store.settings.hasAcceptedDisclaimer)) {
            DisclaimerView()
                .interactiveDismissDisabled()
        }
        .task {
            ActivityController.removeDuplicateNightOuts(context: context)
            ReminderService.shared.becomeDelegate()
            ReminderService.shared.seedDefaults(context: context, store: store)
            let ctx = context
            let st = store
            VoiceService.shared.configure(settings: store.settings) {
                RulesEngine.status(ActivityController.recentSnapshots(context: ctx, settings: st.settings), now: .now, config: st.settings.ruleConfig)
            }
            PhoneWatchBridge.shared.configure(context: context, store: store)
            AutoDriveDetector.shared.configure(context: context, settings: store.settings)
            ActivityController.refreshSideEffects(context: context, settings: store.settings)
            await NotificationService.shared.requestAuthorization()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                ActivityController.refreshSideEffects(context: context, settings: store.settings)
            }
        }
        .onChange(of: store.settings) { _, newValue in
            store.save()
            AutoDriveDetector.shared.update(settings: newValue)
            ActivityController.refreshSideEffects(context: context, settings: newValue)
        }
    }
}
