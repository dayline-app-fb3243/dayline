import SwiftUI
import SwiftData
import UserNotifications
import UIKit

@main
struct DaylineApp: App {
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    private let isDemo = SampleMode.on
    @AppStorage("onboarding.done") private var onboardingDone = false
    @AppStorage("auth.userID") private var signedInUserID = ""

    init() {
        let args = ProcessInfo.processInfo.arguments
        // Yes / No actions for check-in questions; answers arrive even when the app isn't open.
        MainActor.assumeIsolated { CheckInService.registerCategories() }
        // Seeded demo build opens the reviewed sample, while -onboarding forces the first-launch tour.
        if SampleMode.on { UserDefaults.standard.set(!args.contains("-onboarding"), forKey: "onboarding.done") }
        // Every demo run starts on the default Dayline background (the tour picks Sunset later on).
        if SampleMode.on { UserDefaults.standard.removeObject(forKey: "background.preset") }
        if let i = args.firstIndex(of: "-background"), i + 1 < args.count { UserDefaults.standard.set(args[i + 1], forKey: "background.preset") }
        if let i = args.firstIndex(of: "-factorIcons"), i + 1 < args.count { UserDefaults.standard.set(args[i + 1], forKey: "factorIcons") }
        // Demo tour runs as a signed-in sample user (so Sign Out shows); onboarding runs start signed out.
        if SampleMode.on {
            let d = UserDefaults.standard
            if args.contains("-onboarding") { ["auth.userID", "auth.name", "auth.email", "auth.provider"].forEach { d.removeObject(forKey: $0) } }
            else { d.set("demo", forKey: "auth.userID"); d.set("Alex Kim", forKey: "auth.name"); d.set("alex@example.com", forKey: "auth.email"); d.set("apple", forKey: "auth.provider") }
        }
    }

    /// Widget design screenshots: -widgetDesign N -widgetPage P opens that design's page only.
    private static var galleryDesign: WidgetDesign? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-widgetDesign"), i + 1 < a.count, let n = Int(a[i + 1]) else { return nil }
        return WidgetDesign.all.first { $0.id == n }
    }
    private static var galleryPage: Int {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-widgetPage"), i + 1 < a.count else { return 1 }
        return Int(a[i + 1]) ?? 1
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("-weekWidgetSize") {
                    WeekWidgetSizePreview()
                } else if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-widgetConcept"),
                   ProcessInfo.processInfo.arguments.count > i + 1,
                   let n = Int(ProcessInfo.processInfo.arguments[i + 1]) {
                    WidgetConceptsGallery(concept: n)
                } else if let d = Self.galleryDesign {
                    WidgetDesignGalleryView(design: d, page: Self.galleryPage)
                } else if onboardingDone && !signedInUserID.isEmpty {
                    RootView().task { await startUp() }
                } else {
                    OnboardingFlow()
                }
            }
            // Back, close and alert buttons in the label color like iOS; switches, links and main buttons stay blue.
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
        #if DEBUG
        if !SampleMode.on && ProcessInfo.processInfo.arguments.contains("-testJournalMediaGroup") {
            // UI-test fixture: one composer save stores text, three photos and a voice note.
            // All five records share the same ID and must count/display as one entry.
            let group = UUID().uuidString
            for index in 0..<4 {
                let entry = JournalEntry(date: .now.addingTimeInterval(Double(index)), kind: index == 0 ? .text : .photo,
                                         text: index == 0 ? "A walk with photos" : "")
                entry.groupID = group
                if index == 0 { entry.title = "Walk with photos" }
                if index > 0 { entry.thumbnail = UIImage(systemName: "photo")?.pngData() }
                context.insert(entry)
            }
            let voice = JournalEntry(date: .now.addingTimeInterval(4), kind: .voice, audioDuration: 12)
            voice.groupID = group
            context.insert(voice)
            try? context.save()
        }
        #endif
        if isDemo {
            DemoData.seed(context)
            if ProcessInfo.processInfo.arguments.contains("-demoNativeBanner") {
                Task {
                    await Notifications.requestPermission()
                    // Permission dialog may remain open; the native banner is scheduled after it is dismissed.
                    try? await Task.sleep(for: .seconds(4))
                    let content = UNMutableNotificationContent()
                    content.title = "Dayline notification test"
                    content.body = "This is an iOS notification from Dayline."
                    content.sound = .default
                    let request = UNNotificationRequest(identifier: "demo-native-banner", content: content,
                                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
                    do { try await UNUserNotificationCenter.current().add(request) }
                    catch { NSLog("Dayline notification request failed: %@", String(describing: error)) }
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-demoAllNotifications") {
                Task {
                    await Notifications.requestPermission()
                    try? await Task.sleep(for: .seconds(3))
                    for kind in CheckInService.Kind.allCases {
                        await CheckInService.ask(kind, detail: "Demo notification preview", force: true)
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    await Notifications.followRequest(from: "Maya")
                    await Notifications.previewScoreReached()
                    await Notifications.previewJournalReminder()
                    UserDefaults.standard.set(true, forKey: "demo.notifications.sent")
                }
            }
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
