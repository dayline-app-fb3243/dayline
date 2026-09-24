import SwiftUI
import SwiftData

@main
struct DaylineApp: App {
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    private let isDemo = SampleMode.on
    @AppStorage("onboarding.done") private var onboardingDone = false

    init() {
        let args = ProcessInfo.processInfo.arguments
        // Yes / No actions for check-in questions; answers arrive even when the app isn't open.
        MainActor.assumeIsolated { CheckInService.registerCategories() }
        // Demo runs skip onboarding unless -onboarding is passed (used to record the first-launch flow).
        if args.contains("-demo") { UserDefaults.standard.set(!args.contains("-onboarding"), forKey: "onboarding.done") }
        // Every demo run starts on the default Dayline background (the tour picks Sunset later on).
        if args.contains("-demo") { UserDefaults.standard.removeObject(forKey: "background.preset") }
        // Demo tour runs as a signed-in sample user (so Sign Out shows); onboarding runs start signed out.
        if args.contains("-demo") {
            let d = UserDefaults.standard
            if args.contains("-onboarding") { ["auth.userID", "auth.name", "auth.email", "auth.provider"].forEach { d.removeObject(forKey: $0) } }
            else { d.set("demo", forKey: "auth.userID"); d.set("Alex Kim", forKey: "auth.name"); d.set("alex@example.com", forKey: "auth.email"); d.set("apple", forKey: "auth.provider") }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("-demo.rings") {
                    RingSamplesView()
                } else if onboardingDone {
                    RootView().task { await startUp() }
                } else {
                    OnboardingFlow()
                }
            }
            // Preview flag "chrome.style" (David picks): now = blue back/close/alert buttons;
            // B = black like iOS (label color); C = gray. Switches, links and main buttons stay blue.
            .tint(ChromeStyle.tint)
            .toggleStyle(SwitchToggleStyle(tint: Theme.accent))
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
            // Screenshot runs: show real check-in notifications (Apple's Yes / No actions).
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-demoCheckIn") || args.contains("-demoCheckInAll") {
                UserDefaults.standard.set(true, forKey: CheckInService.enabledKey)
                Task {
                    await Notifications.requestPermission()
                    try? await Task.sleep(for: .seconds(4))
                    if args.contains("-demoCheckIn") {
                        await CheckInService.ask(.sleep, detail: "Your phone is at home and charging. Yes ends today here.", force: true)
                    } else {
                        for (k, d) in [(CheckInService.Kind.wake, "Yes sets your wake-up time to 7:02 AM."),
                                       (.run, "Yes adds it to your timeline."),
                                       (.grocery, "You\u{2019}re at Whole Foods Market."),
                                       (.gym, "You\u{2019}re at Iron Works Gym. Yes ticks off Gym on today\u{2019}s plan.")] {
                            await CheckInService.ask(k, detail: d, force: true)
                            try? await Task.sleep(for: .seconds(1))
                        }
                    }
                }
            }
        } else {
            LocationService.shared.requestPermission()
            LocationService.shared.start()
            DayBoundary.shared.start()
            await Notifications.requestPermission()
            DayBoundary.shared.requestMotion()
        }
        await DayRefresher.refresh(context: context)
    }
}
