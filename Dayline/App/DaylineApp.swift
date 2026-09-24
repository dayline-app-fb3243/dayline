import SwiftUI
import SwiftData

@main
struct DaylineApp: App {
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    private let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")
    @AppStorage("onboarding.done") private var onboardingDone = false

    init() {
        let args = ProcessInfo.processInfo.arguments
        // Demo runs skip onboarding unless -onboarding is passed (used to record the first-launch flow).
        if args.contains("-demo") { UserDefaults.standard.set(!args.contains("-onboarding"), forKey: "onboarding.done") }
        // Every demo run starts on the default Dayline background (the tour picks Sunset later on).
        if args.contains("-demo") { UserDefaults.standard.removeObject(forKey: "background.preset") }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingDone {
                    RootView().task { await startUp() }
                } else {
                    OnboardingFlow()
                }
            }
            .tint(Theme.accent)   // one blue accent on every screen
            .preferredColorScheme(Appearance(rawValue: appearanceRaw)?.scheme)
        }
        .modelContainer(ModelStore.container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await DayRefresher.refresh(context: ModelStore.container.mainContext) }
            case .background:
                BackgroundRefresh.schedule()
            default: break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await Task { @MainActor in
                await DayRefresher.refresh(context: ModelStore.container.mainContext)
                BackgroundRefresh.schedule()
            }.value
        }
    }

    @MainActor
    private func startUp() async {
        let context = ModelStore.container.mainContext
        if isDemo {
            DemoData.seed(context)
        } else {
            LocationService.shared.requestPermission()
            LocationService.shared.start()
            await Notifications.requestPermission()
        }
        await DayRefresher.refresh(context: context)
    }
}
