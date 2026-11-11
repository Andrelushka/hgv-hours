import SwiftUI
import SwiftData

/// Handles iOS relaunching the app in the background (e.g. after it was closed and the lorry started moving),
/// so in-cab recording, alerts and widgets carry on without opening the app.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if launchOptions?[.location] != nil {
            MainActor.assumeIsolated {
                let settings = SettingsStore().settings
                let context = StoreSetup.shared.mainContext
                AutoDriveDetector.shared.configure(context: context, settings: settings)
                ActivityController.refreshSideEffects(context: context, settings: settings)
            }
        }
        return true
    }
}

@main
struct HGVTimeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settingsStore = SettingsStore()
    private let container = StoreSetup.shared

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
    @State private var locked = false
    @State private var backgroundedAt: Date?
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "play.circle") }
            HoursView()
                .tabItem { Label("Hours", systemImage: "gauge.with.dots.needle.67percent") }
            DriverLogView()
                .tabItem { Label("Driver log", systemImage: "list.bullet.rectangle.portrait") }
            JobsTab()
                .tabItem { Label("Jobs", systemImage: "shippingbox") }
            EarningsTab()
                .tabItem { Label("Earnings", systemImage: "sterlingsign.circle") }
        }
        .sheet(isPresented: .constant(!store.settings.hasAcceptedDisclaimer)) {
            DisclaimerView()
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: Binding(
            get: { store.settings.hasAcceptedDisclaimer && !store.settings.profileCreated },
            set: { _ in })) {
            NavigationStack { ProfileView(registering: true) }
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
        .overlay {
            if locked {
                LockScreenView { withAnimation { locked = false } }
                    .transition(.opacity)
            }
        }
        .onAppear { if store.settings.lockEnabled { locked = true } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                backgroundedAt = .now
                // Make sure everything is saved and alerts/widgets are up to date before iOS may close the app.
                try? context.save()
                store.save()
                ActivityController.refreshSideEffects(context: context, settings: store.settings)
            }
            if phase == .active, store.settings.lockEnabled, let since = backgroundedAt,
               Date.now.timeIntervalSince(since) >= Double(store.settings.lockAfterMinutes * 60) {
                locked = true
            }
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
