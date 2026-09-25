import XCTest
import CoreLocation
import UIKit

/// Walks through every screen with demo data. CI records the simulator screen while these run,
/// which produces the preview videos, and saves a screenshot of each screen.
final class DemoTourTests: XCTestCase {
    static let shotDir = "/tmp/dayline-shots"

    /// A time zone where the local time is about 9:30 AM right now, so the demo day looks like the design.
    static var morningZone: String { zone(localHour: 9) }

    /// A POSIX zone where the local hour is about `localHour` right now.
    static func zone(localHour: Int) -> String {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let hour = utc.component(.hour, from: .now)
        var offset = (localHour - hour + 24) % 24
        if offset > 14 { offset -= 24 }
        // POSIX Etc zones have the sign flipped: Etc/GMT-8 is UTC+8.
        return offset == 0 ? "UTC" : "Etc/GMT\(offset > 0 ? "-" : "+")\(abs(offset))"
    }

    /// Today greeting follows the clock: evening and night versions.
    func testZGreetingByTime() {
        for (hour, name) in [(19, "10e-today-evening"), (23, "10n-today-night")] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo"]
            app.launchEnvironment["TZ"] = Self.zone(localHour: hour)
            app.launch()
            _ = app.descendants(matching: .any)["todayGreeting"].waitForExistence(timeout: 8)
            pause(2); shot(name)
            app.terminate()
        }
    }

    /// Check-in questions: banner, press-and-hold Yes / No, the answer, then the list.
    func testZCheckIns() {
        let spring = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        func allowAlert() {
            let allow = spring.buttons["Allow"]
            if allow.waitForExistence(timeout: 4) { allow.tap() }
        }
        func find(_ text: String) -> XCUIElement {
            spring.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoCheckIn"]
        app.launchEnvironment["TZ"] = Self.zone(localHour: 23)
        app.launch()
        allowAlert()
        XCUIDevice.shared.press(.home)
        let banner = find("Going to sleep")
        if banner.waitForExistence(timeout: 10) {
            pause(0.6); shot("80-checkin-banner")
            banner.press(forDuration: 1.4); pause(1.2); shot("81-checkin-actions")
            let yes = spring.buttons["Yes"]
            if yes.waitForExistence(timeout: 3) { yes.tap() }
            _ = find("Good night").waitForExistence(timeout: 8); pause(0.8); shot("82-checkin-answered")
        }
        app.terminate()
        app.launchArguments = ["-demo", "-demoCheckInAll"]
        app.launchEnvironment["TZ"] = Self.zone(localHour: 18)
        app.launch()
        allowAlert()
        XCUIDevice.shared.press(.home)
        _ = find("At the gym").waitForExistence(timeout: 15); pause(5)
        // Notification Center: swipe down from the top-left corner.
        let start = spring.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.005))
        start.press(forDuration: 0.1, thenDragTo: spring.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.7)))
        pause(1.5); shot("83-checkins-list")
        XCUIDevice.shared.press(.home)
    }

    func testInvitePrefilledMessages() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1)
        tab(app, "Insights"); pause(1)
        tapID(app, "streakCard"); pause(1)
        tapID(app, "peopleButton"); pause(1)
        app.swipeUp(); pause(0.5)
        let invite = app.descendants(matching: .any)["invite-Maya Cohen"].firstMatch
        if invite.waitForExistence(timeout: 4) { invite.tap(); pause(2) }
        shot("invite-prefilled-native-compose")
    }

    func testInviteSMSFallback() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoSMSFallback"]
        app.launch(); pause(1)
        tab(app, "Insights"); pause(1)
        tapID(app, "streakCard"); pause(1)
        tapID(app, "peopleButton"); pause(1)
        app.swipeUp(); pause(0.5)
        let invite = app.descendants(matching: .any)["invite-Maya Cohen"].firstMatch
        if invite.waitForExistence(timeout: 4) { invite.tap(); pause(2) }
        shot("invite-sms-app-fallback")
    }


    /// A continuous interaction pass, recorded as a simulator video by shots.yml.
    /// Static snapshots alone cannot prove the tabs, back controls or composer respond.
    func testInteractionSweepVideo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-appearance", "light"]
        app.launch(); pause(1)
        for name in ["Today", "Timeline", "Insights", "Journal", "Profile", "Journal", "Timeline"] {
            tab(app, name); pause(0.7); app.swipeUp(); pause(0.5); app.swipeDown(); pause(0.5)
        }
        tab(app, "Journal")
        tapID(app, "journalSearch"); pause(0.7)
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        field.tap(); field.typeText("Blue Door Coffee"); pause(1.5)
        XCTAssertTrue(app.descendants(matching: .any)["searchHit"].firstMatch.exists)
        shot("sweep-search-suggestions")
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists { cancel.tap() } else { goBack(app) }
        pause(0.5)
        tab(app, "Journal"); tapID(app, "newEntry"); pause(0.7)
        let title = app.descendants(matching: .any)["entryTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        title.tap(); title.typeText("Morning note"); pause(0.4)
        // iOS simulator may show a one-time swipe-typing tutorial over the keyboard.
        // Clear it before recording or screenshots; do not confuse this system overlay with app UI.
        let tutorialContinue = app.buttons["Continue"].firstMatch
        if tutorialContinue.waitForExistence(timeout: 2) { tutorialContinue.tap(); pause(0.4) }
        let mic = app.descendants(matching: .any)["voiceMic"].firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 4))
        mic.press(forDuration: 1.3)
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 2) { allow.tap(); mic.press(forDuration: 1.3) }
        pause(1.2); shot("sweep-voice-composer")
        tapID(app, "saveEntry"); pause(1)
        tab(app, "Profile"); tapID(app, "checkLocationRow"); pause(0.7)
        tapID(app, "check-1"); pause(0.7)
        tapID(app, "check-10"); pause(0.7)
        let thumb = app.descendants(matching: .any)["thumb-10"].firstMatch
        if thumb.waitForExistence(timeout: 3) { thumb.tap(); pause(1); shot("sweep-location-expanded") }
    }

    func testDemoProviderPages() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-onboarding"]
        app.launch(); pause(1)
        tapID(app, "splashContinue"); pause(0.8)
        tapID(app, "signInContinue"); pause(0.9)
        XCTAssertTrue(app.buttons["appleDemoContinue"].waitForExistence(timeout: 4))
        shot("provider-apple-demo")
        app.buttons["Close"].firstMatch.tap(); pause(0.8)
        tapID(app, "signInOption-Google"); tapID(app, "signInContinue"); pause(0.9)
        XCTAssertTrue(app.buttons["googleDemoAccount"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Close"].firstMatch.exists)
        shot("provider-google-demo")
    }

    func testAuthParallelSubtitles() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-onboarding"]
        app.launch(); pause(1)
        tapID(app, "splashContinue"); pause(1)
        XCTAssertTrue(app.staticTexts["Uses your Apple Account"].exists)
        XCTAssertTrue(app.staticTexts["Uses your Google Account"].exists)
        shot("auth-parallel-provider-subtitles")
    }

    func testAuthLabelOptions() {
        for variant in ["A", "B", "C"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-onboarding", "-auth.emailLabel", variant]
            app.launch(); pause(1)
            tapID(app, "splashContinue"); pause(1)
            XCTAssertTrue(app.buttons["signInOption-Email"].waitForExistence(timeout: 4))
            shot("auth-label-\(variant)")
            app.terminate()
        }
    }

    func testSignOutAndReturningSignIn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1)
        tab(app, "Profile"); pause(1)
        tapID(app, "accountRow"); pause(1)
        tapID(app, "accountSignOut")
        app.alerts.buttons["Sign Out"].tap(); pause(2)
        XCTAssertTrue(app.descendants(matching: .any)["splash"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.tabBars.buttons["Profile"].exists)
        shot("auth-after-sign-out")
        tapID(app, "splashContinue"); pause(1)
        shot("auth-returning-sign-in")
        tapID(app, "signInContinue"); pause(1)
        let demo = app.buttons["appleDemoContinue"]
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        demo.tap(); pause(3)
        XCTAssertFalse(app.descendants(matching: .any)["splash"].firstMatch.exists)
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists)
        shot("auth-returning-restored")
    }

    func testQuotedSiriExamples() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-appearance", "light"]
        app.launch(); pause(1)
        tab(app, "Profile"); pause(1)
        tapID(app, "useWithSiriRow"); pause(1)
        XCTAssertTrue(app.staticTexts["“Hey Siri, take me back with Dayline”"].exists)
        shot("siri-quoted-examples-light")
    }

    func testNewAccountSplashPaths() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-onboarding"]
        app.launch(); pause(2)
        XCTAssertTrue(app.buttons["splashContinue"].exists)
        XCTAssertFalse(app.buttons["splashGoogle"].exists)
        XCTAssertFalse(app.buttons["splashSignIn"].exists)
        shot("auth-first-launch-splash")
    }

    func testCheckLocationInteractionVideo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-appearance", "light"]
        app.launch(); pause(1)
        tab(app, "Profile"); pause(1)
        tapID(app, "checkLocationRow"); pause(3)
        shot("location-before-interval")
        tapID(app, "check-10"); pause(1)
        shot("location-after-ten-minutes")
        let thumbnail = app.descendants(matching: .any)["thumb-10"].firstMatch
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
        thumbnail.tap(); pause(0.8)
        XCTAssertTrue(app.descendants(matching: .any)["bigCard"].firstMatch.exists)
        shot("location-enlarged-map")
    }

    func testJournalReminderToggle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1)
        tab(app, "Profile"); pause(1)
        tapID(app, "notificationsRow"); pause(1)
        let row = app.switches["Daily Journal Reminder"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["journalReminderTime"].exists)
        XCTAssertTrue(app.staticTexts["When on, a reminder arrives 15 minutes before your bedtime set in Your Schedule."].exists)
        shot("journal-reminder-off")
        if row.value as? String == "1" { row.tap() }
        row.tap()
        XCTAssertEqual(row.value as? String, "1")
        shot("journal-reminder-on")
    }

    func testNativeNotificationBanner() throws {
        let app = XCUIApplication()
        let spring = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launchArguments = ["-demo", "-demoNativeBanner"]
        app.launch()
        let allow = spring.buttons["Allow"]
        if allow.waitForExistence(timeout: 12) { allow.tap() }
        let banner = spring.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Dayline notification test")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "No native OS notification banner appeared")
        shot("native-notification-banner")
    }

    func testAllNotificationPreviews() throws {
        let app = XCUIApplication()
        let spring = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launchArguments = ["-demo", "-demoAllNotifications"]
        app.launch()
        let allow = spring.buttons["Allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 15), "Native notification permission prompt did not appear")
        shot("notification-permission-system-prompt")
        allow.tap()
        XCTAssertFalse(allow.waitForExistence(timeout: 5), "Notification permission prompt did not dismiss")
        pause(8)
        XCUIDevice.shared.press(.home)
        pause(4)
        let start = spring.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.005))
        start.press(forDuration: 0.1, thenDragTo: spring.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.7)))
        pause(2)
        shot("all-notification-types-lock-screen")
    }

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: Self.shotDir, withIntermediateDirectories: true)
    }

    /// Inspect the actual first launch of whichever Xcode variant was built, with no launch arguments.
    /// Clean Empty build only: capture the real onboarding sequence without demo seeding.
    func testEmptyOnboardingTour() throws {
        let app = XCUIApplication()
        app.launch()
        pause(4); shot("empty-01-welcome")
        tapID(app, "splashContinue"); pause(1); shot("empty-02-sign-in")
        tapID(app, "signInOption-Email"); pause(1); shot("empty-03-email-choice")
        tapID(app, "signInContinue"); pause(1); shot("empty-04-email")
        let field = app.textFields["emailField"]
        if field.waitForExistence(timeout: 4) { field.tap(); field.typeText("new.user@example.com") }
        shot("empty-05-email-entry")
    }

    private func emptyTabs(_ scheme: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.done", "YES", "-testSignedIn", "-appearance", scheme.lowercased()]
        app.launch(); pause(2)
        let locationPrompt = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let allowLocation = locationPrompt.buttons["Allow While Using App"]
            let keep = locationPrompt.buttons["Keep Only While Using"]
            if allowLocation.waitForExistence(timeout: 2) { allowLocation.tap(); pause(1) }
            else if keep.waitForExistence(timeout: 1) { keep.tap(); pause(1) }
            else { break }
        }
        XCTAssertTrue(app.descendants(matching: .any)["todayEmptyState"].firstMatch.waitForExistence(timeout: 8))
        let add = app.buttons["addJournalEmpty"]
        XCTAssertTrue(add.exists && add.isHittable)
        shot("empty-today-\(scheme.lowercased())")
        for tab in ["Timeline", "Insights", "Journal", "Profile"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing \(tab) tab")
            button.tap(); pause(3)
            if tab == "Timeline" {
                XCTAssertTrue(app.descendants(matching: .any)["mapCard"].firstMatch.exists, "With permission, fresh Timeline has a real map")
                XCTAssertTrue(app.descendants(matching: .any)["timelineEmptyState"].firstMatch.exists, "Explain what data is still needed")
            }
            shot("empty-\(tab.lowercased())-\(scheme.lowercased())")
        }
    }

    func testJournalMediaDialogDark() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.done", "YES", "-testSignedIn", "-appearance", "dark"]
        app.launch()
        app.tabBars.buttons["Journal"].tap()
        tapID(app, "newEntry")
        let add = app.buttons["entryAddMedia"]
        XCTAssertTrue(add.waitForExistence(timeout: 6))
        add.tap(); pause(1)
        XCTAssertTrue(app.buttons["Photo and Video Library"].waitForExistence(timeout: 4))
        shot("journal-media-dialog-dark")
    }

    func testNearbyGymAndNameSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1)
        let locationPrompt = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowLocation = locationPrompt.buttons["Allow While Using App"]
        if allowLocation.waitForExistence(timeout: 3) { allowLocation.tap() }
        app.tabBars.buttons["Profile"].tap(); pause(1)
        tapID(app, "Your Schedule"); pause(1)
        let gym = app.descendants(matching: .any)["gymLocation"].firstMatch
        if !gym.exists { app.swipeUp() }
        XCTAssertTrue(gym.waitForExistence(timeout: 5))
        gym.tap(); pause(7)
        XCTAssertTrue(app.staticTexts["Gyms nearby"].exists)
        XCTAssertTrue(app.buttons["placeResult"].firstMatch.exists, "Apple Maps returned no nearby gym")
        shot("gym-nearby")
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Planet Fitness"); pause(7)
        XCTAssertTrue(app.buttons["placeResult"].firstMatch.exists, "Apple Maps returned no named gym")
        shot("gym-name-search")
    }

    func testProfileCleanNavigationRows() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.done", "YES", "-testSignedIn", "-appearance", "dark"]
        app.launch(); pause(1)
        app.tabBars.buttons["Profile"].tap(); pause(1)
        for id in ["yourScheduleRow", "placesRow", "backgroundRow", "checkLocationRow"] {
            let row = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(row.exists)
        }
        shot("profile-clean-navigation-rows")
    }

    func testDefaultWorkHoursWeekdays() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.done", "YES", "-testSignedIn"]
        app.launch(); pause(1)
        app.tabBars.buttons["Profile"].tap(); pause(1)
        tapID(app, "Your Schedule"); pause(1)
        let weekdays = app.descendants(matching: .any)["workBlock-Weekdays"].firstMatch
        XCTAssertTrue(weekdays.waitForExistence(timeout: 6))
        XCTAssertTrue(weekdays.label.contains("9:00") && weekdays.label.contains("5:00"))
        shot("default-work-hours-weekdays")
    }

    func testPeopleSearchFiltersContacts() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-testPeopleSearch"]
        app.launch(); pause(1)
        app.tabBars.buttons["Insights"].tap(); pause(1)
        tapID(app, "streakCard"); pause(1)
        tapID(app, "peopleButton"); pause(1)
        XCTAssertTrue(app.descendants(matching: .any)["contact-Casey Morgan"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["contact-Taylor Reed"].firstMatch.exists)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("0134"); pause(1)
        XCTAssertTrue(app.descendants(matching: .any)["contact-Casey Morgan"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["contact-Taylor Reed"].firstMatch.exists)
        shot("people-search-filtered-number")
    }

    func testOneJournalMultipleMediaOneScheduleRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.done", "YES", "-testSignedIn", "-appearance", "dark", "-testJournalMediaGroup"]
        app.launch(); pause(1)
        let schedule = app.descendants(matching: .any)["todaySchedule"].firstMatch
        XCTAssertTrue(schedule.waitForExistence(timeout: 8))
        let journalRows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "scheduleRow-")).allElementsBoundByIndex
            .filter { $0.label.localizedCaseInsensitiveContains("Walk with photos") }
        XCTAssertEqual(journalRows.count, 1)
        shot("one-journal-with-photos-voice-one-row")
    }

    func testEmptyTabsDark() { emptyTabs("Dark") }
    func testEmptyTabsLight() { emptyTabs("Light") }

    /// The normal test target's -demo flag uses the same seed path as the Demo Xcode target.
    func testScoreWidgetRingLight() { scoreWidgetRing("light", page: "1") }
    func testScoreWidgetRingDark() { scoreWidgetRing("dark", page: "2") }
    private func scoreWidgetRing(_ appearance: String, page: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-appearance", appearance, "-widgetDesign", "14", "-widgetPage", page]
        app.launch(); pause(2)
        shot("score-widget-\(appearance)")
    }

    func testFreshDemoHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(5)
        XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 8))
        tab(app, "Timeline"); pause(3)
        XCTAssertTrue(app.staticTexts["Gym"].exists || app.staticTexts["Blue Door Coffee"].exists)
        shot("fresh-demo-timeline-day")
        tapSegment(app, "Month"); pause(3)
        shot("fresh-demo-timeline-month")
        tab(app, "Insights"); pause(2)
        shot("fresh-demo-insights")
        tab(app, "Journal"); pause(2)
        XCTAssertTrue(app.buttons["journalCard"].firstMatch.exists)
        shot("fresh-demo-journal-history")
    }

    func testVariantFirstLaunch() throws {
        let app = XCUIApplication()
        app.launch(); pause(3)
        shot("variant-first-launch")
    }

    /// First launch as a new user: splash, intro pages, Sign in with Apple, phone, permissions.
    func testOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-onboarding"]
        app.launchEnvironment["TZ"] = Self.morningZone
        app.launch()
        pause(1.5); shot("01-splash")
        tapID(app, "splashContinue")
        if !app.descendants(matching: .any)["signInOption-Apple"].waitForExistence(timeout: 3) { app.buttons["Continue"].firstMatch.tap() }
        pause(1.5); shot("02-sign-in-sheet")
        tapID(app, "signInOption-Google"); pause(0.8); shot("02b-sign-in-google")
        tapID(app, "signInOption-Email"); pause(0.8); shot("02c-sign-in-email")
        tapID(app, "signInOption-Apple"); pause(0.5)
        tapID(app, "signInContinue"); pause(1.8); shot("05c-apple-sheet")
        tapID(app, "appleDemoContinue"); pause(1.5)
        let phone = app.textFields["phoneField"]; _ = phone.waitForExistence(timeout: 5); phone.tap(); phone.typeText("2015550142"); pause(1); shot("06a-phone")
        tapID(app, "setupPrimary"); pause(1.5)
        let codeField = app.textFields["codeField"]; _ = codeField.waitForExistence(timeout: 5); codeField.tap(); codeField.typeText("4829"); pause(1); shot("06b-code")
        codeField.typeText("13"); tapID(app, "setupPrimary"); pause(1.5); shot("06-permissions")
        tapID(app, "permissionsContinue"); pause(1.2); shot("06b-permissions-photos")
        tapID(app, "permissionsContinue"); pause(1.2); shot("06b2-permissions-contacts")
        tapID(app, "permissionsContinue")
        let contactsAllow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Full Access"]
        if contactsAllow.waitForExistence(timeout: 4) { shot("06b3-contacts-system-prompt"); contactsAllow.tap() }
        pause(1.2); shot("06c-permissions-mic")
        tapID(app, "permissionsContinue"); pause(1.2); shot("06c2-permissions-motion")
        tapID(app, "permissionsContinue"); pause(1.2); shot("06c3-permissions-health")
        tapID(app, "permissionsContinue"); pause(1.2); shot("06c4-permissions-reminders")
        tapID(app, "permissionsContinue"); pause(1.2); shot("06d-permissions-notifications")
        tapID(app, "permissionsContinue"); pause(3); shot("07-today-after-sign-in")
    }

    /// The email sign-up path (screenshots only).
    func testOnboardingEmail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-onboarding"]
        app.launchEnvironment["TZ"] = Self.morningZone
        app.launch()
        pause(1.5)
        tapID(app, "splashContinue"); pause(1.5)
        tapID(app, "signInOption-Email"); pause(0.5)
        tapID(app, "signInContinue"); pause(1.8)
        let email = app.textFields["emailField"]; _ = email.waitForExistence(timeout: 5); email.tap(); email.typeText("alex@example.com"); pause(1); shot("05a-email")
        tapID(app, "setupPrimary"); pause(1.5)
        let eCode = app.textFields["emailCodeField"]; _ = eCode.waitForExistence(timeout: 5); eCode.tap(); eCode.typeText("5710"); pause(1); shot("05b-email-code")
    }

    /// Just the screens changed in the latest round, for a quick picture set.
    func testChangedScreens() throws {
        var app = XCUIApplication()
        app.launchArguments = ["-demo", "-onboarding"]
        app.launchEnvironment["TZ"] = Self.morningZone
        app.launch()
        pause(1.5)
        tapID(app, "splashContinue"); pause(1.5)
        tapID(app, "signInOption-Email"); pause(0.5)
        tapID(app, "signInContinue"); pause(1.8)
        let email = app.textFields["emailField"]; _ = email.waitForExistence(timeout: 5); email.tap(); email.typeText("alex@example.com"); pause(1); shot("c1-email")
        tapID(app, "setupPrimary"); pause(1.5)
        let eCode = app.textFields["emailCodeField"]; _ = eCode.waitForExistence(timeout: 5); eCode.tap(); eCode.typeText("571042"); pause(1); shot("c2-email-code")
        tapID(app, "setupPrimary"); pause(1.8)
        let phone = app.textFields["phoneField"]
        if phone.waitForExistence(timeout: 5) {
            phone.tap(); phone.typeText("2015550142"); tapID(app, "setupPrimary"); pause(1.5)
            let code = app.textFields["codeField"]; _ = code.waitForExistence(timeout: 5); code.tap(); code.typeText("482913"); pause(1); shot("c3-phone-code")
        }
        app.terminate()

        // Main screens, David's picks, one launch.
        app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launchEnvironment["TZ"] = Self.morningZone
        app.launch(); pause(1.5)
        tab(app, "Today"); pause(2); shot("c10a-today")
        tapID(app, "scoreCard"); pause(2); shot("c10b-day-score"); app.swipeUp(); pause(1.2); shot("c10c-day-score-scrolled")
        goBack(app)
        tab(app, "Timeline"); pause(3); shot("c11-timeline")
        app.swipeUp(); pause(1.2); shot("c11b-timeline-scrolled")
        let office = app.descendants(matching: .any)["stop-Office"].firstMatch
        if office.waitForExistence(timeout: 3) { office.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap(); pause(2); shot("c12-stop"); goBack(app) }
        app.swipeDown(); pause(1)
        let card = app.descendants(matching: .any)["mapCard"].firstMatch
        if card.waitForExistence(timeout: 3) { card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap(); pause(2.5); shot("c8-full-map"); backToTabs(app) }
        tab(app, "Insights"); pause(1.5); shot("c20-insights-month")
        tapSegment(app, "Day"); pause(1.5); shot("c13-insights-day")
        tapSegment(app, "Month"); pause(1.2)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Streak'")).firstMatch.tap(); pause(2); shot("c17-streak")
        app.swipeUp(); pause(0.8); app.swipeUp(); pause(1.2); shot("c17b-people")
        backToTabs(app)
        tab(app, "Journal"); pause(2); shot("c19-journal")
        let jc = app.buttons["journalCard"].firstMatch
        if jc.waitForExistence(timeout: 3) { jc.tap(); pause(2); shot("c19b-journal-edit"); app.buttons["Close"].firstMatch.tap(); pause(1.2) }
        tab(app, "Profile"); pause(2); shot("c4-profile")
        app.swipeUp(); pause(1.2); shot("c4a-profile-scrolled"); app.swipeDown(); pause(1)
        tapID(app, "accountRow"); pause(1.8); shot("c4b-account"); goBack(app); pause(1)
        tapID(app, "yourScheduleRow"); pause(1.8); shot("c4c-schedule"); goBack(app); pause(1)
        tapID(app, "checkLocationRow"); pause(1.8); shot("c4d-check-location"); goBack(app); pause(1)
        tapID(app, "notificationsRow"); pause(1.8); shot("c4e-notifications"); goBack(app); pause(1)
        app.swipeUp(); pause(1)
        tapID(app, "yourDataRow"); pause(1.8); shot("c4f-your-data")
        app.terminate()
    }

    func testTour() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launchEnvironment["TZ"] = Self.morningZone
        app.launch()
        pause(3); shot("10-today")
        tapID(app, "scoreCard"); pause(2); shot("14-day-score"); app.swipeUp(); pause(1.2); shot("15-day-score-scrolled")
        app.swipeDown(); pause(0.8)
        // Swipe back through earlier days, like Screen Time.
        app.swipeRight(); pause(1.5); app.swipeRight(); pause(1.5); shot("16-day-score-past")
        app.swipeUp(); pause(1.2); shot("17-day-score-past-scrolled"); app.swipeDown(); pause(0.8)
        tapID(app, "dayTitle"); pause(1.8); shot("18-day-picker")
        app.swipeDown(); pause(1.2)
        tapID(app, "backToToday"); pause(1.5)
        goBack(app)

        tab(app, "Timeline"); pause(3); shot("20-timeline-day")
        let card = app.descendants(matching: .any)["mapCard"].firstMatch
        if card.waitForExistence(timeout: 3) { card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap() }
        pause(2.5); shot("26-full-map")
        tapID(app, "togglePhotos"); pause(1.2); shot("24-full-map-photos-off")
        tapID(app, "togglePhotos"); pause(1)
        tapID(app, "closeMap"); pause(1.5)
        tapSegment(app, "Week"); pause(2.5); shot("21-timeline-week")
        tapSegment(app, "Month"); pause(2.5); shot("22-timeline-month")
        tapSegment(app, "Year"); pause(2.5); shot("23-timeline-year")
        tapSegment(app, "Day"); pause(2)

        // Headline feature, below the day's list: take me back to where I ate 4 days ago.
        app.swipeUp(); pause(1); app.swipeUp(); pause(1.5); shot("11-timeline-scrolled")
        app.swipeDown(); pause(1); app.swipeDown(); pause(1)

        tab(app, "Insights"); pause(2.5); shot("30-insights-month")
        tapID(app, "streakCard"); pause(2); shot("33-streak")
        tapID(app, "friend-Sam"); pause(2); shot("34-friend"); goBack(app)
        tapID(app, "peopleButton"); pause(2); shot("35-people")
        app.swipeUp(); pause(1.2); shot("35b-people-scrolled"); app.swipeDown(); pause(1)
        tapID(app, "person-Sam"); pause(2); shot("36-person-sam"); goBack(app); pause(1)
        tapID(app, "askToShare"); pause(2); shot("37-ask-to-share"); goBack(app); pause(1)
        app.swipeUp(); pause(1)
        tapID(app, "addPerson"); pause(2); shot("38-share-with")
        let shareBtn = app.buttons["Share"].firstMatch
        if shareBtn.waitForExistence(timeout: 2) { shareBtn.tap(); pause(1); shot("38b-share-with-sharing") }
        let sf = app.textFields["shareSearch"]
        if sf.waitForExistence(timeout: 2) {
            sf.tap(); sf.typeText("Ma"); pause(1.5); shot("38c-share-with-search")
            dismissSearch(app)
            pause(1)
        }
        goBack(app); pause(1)
        tapID(app, "invite-Maya Cohen"); pause(2.5); shot("39-invite-sheet")
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 2) { close.tap() } else { app.swipeDown(velocity: .fast) }
        pause(1.5)
        backToTabs(app)
        tab(app, "Insights"); pause(1.5)
        tapSegment(app, "Day"); pause(2.5); shot("31-insights-day")
        tapSegment(app, "Year"); pause(2.5); shot("32-insights-year")
        tapSegment(app, "Month"); pause(2)

        tab(app, "Journal"); pause(2.5); shot("40-journal")
        app.swipeUp(); pause(1.5); app.swipeDown(); pause(1)

        tapID(app, "newEntry"); pause(2.5); shot("50-new-entry")
        let titleField = app.descendants(matching: .any).matching(identifier: "entryTitle").firstMatch
        if titleField.waitForExistence(timeout: 2) {
            titleField.tap(); titleField.typeText("Lunch with the team")
            let bodyField = app.descendants(matching: .any).matching(identifier: "entryBody").firstMatch
            if bodyField.waitForExistence(timeout: 1.5) { bodyField.tap(); bodyField.typeText("Finally tried the cacio e pepe everyone talks about. Worth it.") }
            pause(1); shot("51-new-entry-typed")
            // Voice note: hold the microphone and release to attach.
            let mic = app.descendants(matching: .any).matching(identifier: "voiceMic").firstMatch
            if mic.waitForExistence(timeout: 2) {
                mic.press(forDuration: 1.3)
                let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
                if allow.waitForExistence(timeout: 1.5) { allow.tap(); pause(0.5); mic.press(forDuration: 1.3) }
                pause(1.5); shot("51d-voice-added")
            }
            tapID(app, "saveEntry"); pause(2); shot("52-journal-after-save")
        }
        // Profile > Background: pick a preset and show it behind Today.
        tab(app, "Profile"); pause(2); shot("60-profile")
        tapID(app, "accountRow"); pause(2); shot("60a-account"); goBack(app); pause(1)
        tapID(app, "yourScheduleRow"); pause(2); shot("61-your-schedule")
        app.swipeUp(); pause(1); shot("61b-your-schedule-habits"); app.swipeDown(); pause(1)
        let friday = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'workBlock-'")).element(boundBy: 1)
        if friday.waitForExistence(timeout: 3) { friday.tap(); pause(2); shot("62-work-hours-friday")
            let c = app.navigationBars.buttons.element(boundBy: 0); if c.waitForExistence(timeout: 2) { c.tap() }; pause(1.2) }
        goBack(app); pause(1)
        tapID(app, "placesRow"); pause(2); shot("65-places")
        tapID(app, "place-home"); pause(1.5)
        app.typeText("Apple Park"); pause(3); shot("65b-add-place-search")
        let cx = app.navigationBars.buttons.element(boundBy: 0); if cx.waitForExistence(timeout: 2) { cx.tap() }; pause(1.2)
        goBack(app); pause(1)
        app.swipeUp(); pause(1.2); shot("60b-profile-bottom")
        let siriRow = app.descendants(matching: .any)["useWithSiriRow"].firstMatch
        if siriRow.waitForExistence(timeout: 3) {
            siriRow.tap(); pause(2); shot("70-use-with-siri")
            goBack(app); pause(1.2)
        }
        let policy = app.links["Privacy Policy"].firstMatch
        if policy.waitForExistence(timeout: 3) { policy.tap() } else { tapID(app, "privacyPolicyRow") }
        pause(1.5); shot("66-privacy-policy"); app.swipeUp(); pause(1); shot("66b-privacy-policy-end")
        let closePolicy = app.buttons["Close"].firstMatch
        if closePolicy.waitForExistence(timeout: 2) { closePolicy.tap() } else { app.swipeDown(velocity: .fast) }
        pause(1.2)
        tapID(app, "signOutRow"); pause(1.2); shot("67-sign-out-confirm")
        let cancel = app.alerts.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }
        pause(1)
        for (name, label) in [("68-location-settings", "Location"), ("69-photos-settings", "Photos"), ("69b-notifications-settings", "Notifications")] {
            let row = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            if row.waitForExistence(timeout: 3) { row.tap(); pause(6); shot(name); app.activate(); pause(1.5) }
        }
        let appearance = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Appearance")).firstMatch
        if appearance.waitForExistence(timeout: 3) { appearance.tap(); pause(1.2); shot("60c-appearance-menu"); let sys = app.buttons["System"].firstMatch; if sys.waitForExistence(timeout: 2) { sys.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap() }; pause(0.8) }
        app.swipeDown(); pause(1)
        tapID(app, "checkLocationRow"); pause(2); shot("64-check-location")
        tapID(app, "check-1"); pause(1.2); tapID(app, "check-5"); pause(1.2); goBack(app); pause(1)
        // Hidden Siri demo page: long-press "Your data", then step through all 6 commands.
        let dataRow = app.descendants(matching: .any)["yourDataRow"].firstMatch
        if dataRow.waitForExistence(timeout: 5) {
            dataRow.press(forDuration: 1.6); pause(3)
            for i in 1...6 {
                shot(String(format: "7%d-siri-%d", i, i)); pause(2.5)
                if i < 6 { tapID(app, "siriNext"); pause(3) }
            }
            tapID(app, "widgetsDemoLink"); pause(3); shot("77-widgets"); goBack(app); pause(1)
            goBack(app); pause(1)
        }
        tapID(app, "backgroundRow")
        pause(2); shot("61-background-picker")
        let sunset = app.buttons["Sunset"].firstMatch
        if sunset.waitForExistence(timeout: 3) { sunset.tap() }
        pause(1.5); shot("62-background-sunset")
        goBack(app)
        tapID(app, "yourDataRow"); pause(2); shot("65-your-data")
        tapID(app, "deleteAccount"); pause(1.2); shot("65b-delete-confirm")
        let cancelDelete = app.alerts.buttons["Cancel"].firstMatch
        if cancelDelete.waitForExistence(timeout: 2) { cancelDelete.tap() }
        pause(0.8); goBack(app)
        tab(app, "Today"); pause(1.5); shot("63-today-sunset")
    }

    /// Add the actual extension from SpringBoard; gallery rendering does not count.
    func testInstalledHomeWidget() throws { try installHomeWidget(demo: true) }
    func testInstalledEmptyHomeWidget() throws { try installHomeWidget(demo: false) }

    private func installHomeWidget(demo: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = demo ? ["-demo"] : []
        app.launch(); pause(5)
        XCUIDevice.shared.press(.home); pause(2)
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        shot("widget-install-home-before")
        sb.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.67)).press(forDuration: 1.5)
        pause(1); shot("widget-install-edit-mode")
        let edit = sb.buttons["Edit"].firstMatch
        if edit.waitForExistence(timeout: 3) { edit.tap(); pause(0.5) }
        let add = sb.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add Widget'")).firstMatch
        let plus = sb.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add' OR label == '+' ")).firstMatch
        if add.waitForExistence(timeout: 2) { add.tap() }
        else if plus.waitForExistence(timeout: 2) { plus.tap() }
        else { try (sb.debugDescription).write(toFile: Self.shotDir + "/widget-home-hierarchy.txt", atomically: true, encoding: .utf8); XCTFail("SpringBoard Add Widget action missing"); return }
        pause(1.5); shot("widget-install-gallery")
        let search = sb.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) { search.tap(); search.typeText("Dayline") }
        pause(1); shot("widget-install-search")
        let dayline = sb.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Dayline'")).firstMatch
        XCTAssertTrue(dayline.waitForExistence(timeout: 5), "Dayline missing from iOS widget gallery")
        dayline.tap(); pause(1.5); shot("widget-install-preview")
        let addWidget = sb.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add Widget'")).firstMatch
        XCTAssertTrue(addWidget.waitForExistence(timeout: 5), "Add Widget button missing")
        addWidget.tap(); pause(2)
        let done = sb.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 3) { done.tap() }
        pause(3); shot(demo ? "widget-installed-home" : "widget-installed-empty-home")
        try sb.debugDescription.write(toFile: Self.shotDir + (demo ? "/widget-installed-hierarchy.txt" : "/widget-installed-empty-hierarchy.txt"), atomically: true, encoding: .utf8)
    }

    /// Home Screen shot to check the real app icon (Icon Composer .icon) as iOS draws it.
    func testHomeIcon() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(2)
        XCUIDevice.shared.press(.home); pause(2)
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for i in 0..<4 {
            if sb.icons["Dayline"].exists && sb.icons["Dayline"].isHittable { break }
            sb.swipeLeft(); pause(1.2); _ = i
        }
        pause(1); shot("h1-home-icon")
    }

    /// Same Home Screen shot with the Simulator in Dark mode (the workflow switches appearance for *Dark tests),
    /// to check iOS uses the icon's dark version.
    func testHomeIconDark() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(2)
        XCUIDevice.shared.press(.home); pause(3)
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for i in 0..<4 {
            if sb.icons["Dayline"].exists && sb.icons["Dayline"].isHittable { break }
            sb.swipeLeft(); pause(1.2); _ = i
        }
        pause(1.5); shot("h2-home-icon-dark")
        // Home Screen icon style: long-press, Edit > Customize > Dark (like David's Simulator), then shoot again.
        sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)).press(forDuration: 1.6); pause(1.2)
        let edit = sb.buttons["Edit"].firstMatch
        if edit.waitForExistence(timeout: 3) { edit.tap(); pause(1) }
        let customize = sb.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Customize'")).firstMatch
        if customize.waitForExistence(timeout: 3) { customize.tap(); pause(1.5) }
        shot("h3-customize")
        let dark = sb.buttons.matching(NSPredicate(format: "label ==[c] 'Dark'")).firstMatch
        if dark.waitForExistence(timeout: 3) { dark.tap(); pause(2) }
        shot("h4-customize-dark")
        XCUIDevice.shared.press(.home); pause(1); XCUIDevice.shared.press(.home); pause(2)
        shot("h5-home-icon-dark-style")
    }

    /// Splash options only (map-based D/E/F/G).
    func testSplashDemo() throws {
        for v in ["map", "D", "E", "F", "G"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-onboarding", "-splash.style", v]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.8); shot("pv-splash-\(v)")
            app.terminate()
        }
    }

    /// Splash with real Apple Maps and a street-following route: A standard, B muted + times, C 3D.
    func testSplashMapDemo() throws {
        for v in ["C", "D", "E", "F"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-onboarding", "-splash.map", v]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(6); shot("sm-map-\(v)")
            app.terminate()
        }
    }

    /// Sign-in: small "Continue" pill + ring mark colors (no icon square).
    /// Sign out on Profile, then tap Sign In: the sign-in sheet opens and signs you back in (Apple and Email).
    func testSignOutSignIn() throws {
        for path in ["Apple", "Email"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo"]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5)
            tab(app, "Profile"); pause(1.2)
            app.swipeUp(); app.swipeUp(); pause(0.8)
            tapID(app, "signOutRow"); pause(1)
            let confirm = app.alerts.buttons["Sign Out"].firstMatch
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
            pause(1); app.swipeDown(); app.swipeDown(); pause(1)
            shot("so-\(path)-1-signed-out")
            tapID(app, "accountRow"); pause(1.5); shot("so-\(path)-2-sheet")
            print("SHEETFIT close=\(app.buttons["Close"].firstMatch.frame) continue=\(app.buttons["signInContinue"].frame)")
            if path == "Apple" {
                tapID(app, "signInContinue"); pause(1.5); shot("so-\(path)-3-apple")
                tapID(app, "appleDemoContinue"); pause(2.5)
            } else {
                tapID(app, "signInOption-Email"); pause(0.5); tapID(app, "signInContinue"); pause(1.5)
                let field = app.textFields["emailField"].firstMatch
                if field.waitForExistence(timeout: 3) { field.tap(); field.typeText("me@example.com") }
                shot("so-\(path)-3-email")
                tapID(app, "setupPrimary"); pause(1.5)
                let code = app.textFields["emailCodeField"].firstMatch
                if code.waitForExistence(timeout: 3) { code.typeText("123456") }
                shot("so-\(path)-4-code")
                tapID(app, "setupPrimary"); pause(2.5)
            }
            shot("so-\(path)-5-signed-in")
            tapID(app, "accountRow"); pause(1.5); shot("so-\(path)-6-account")
            app.terminate()
        }
    }

    /// Splash loop M -> P -> Q -> R with slow camera moves and crossfades; keeps going under the sign-in sheet.
    func testSplashLoopVideo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-onboarding"]
        app.launchEnvironment["TZ"] = Self.morningZone
        app.launch()
        pause(4); shot("sl-1-park")
        pause(3.2); shot("sl-2-fade")
        pause(4); shot("sl-3-gym")
        pause(8); shot("sl-4-office")
        pause(8); shot("sl-5-coffee")
        tapID(app, "splashContinue"); pause(4); shot("sl-6-sheet")
        pause(10); shot("sl-7-sheet-later")
        pause(6)
        app.terminate()
    }

    /// Splash G/H/I: C's 3D look, new pins, closer and more top-down.
    func testSplashPinDemo() throws {
        for v in ["G", "H", "I"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-onboarding", "-splash.map", v]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(7); shot("sp-\(v)")
            app.terminate()
        }
    }

    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let mode = ProcessInfo.processInfo.environment["DAYLINE_MODE"] ?? "light"
        try? data.write(to: URL(fileURLWithPath: "\(Self.shotDir)/\(name)-\(mode).png"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapID(_ app: XCUIApplication, _ id: String) {
        let element = app.descendants(matching: .any)[id].firstMatch
        if element.waitForExistence(timeout: 5) { element.tap() }
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        let button = app.tabBars.buttons[name]
        if button.waitForExistence(timeout: 5) { button.tap() }
    }

    private func tapSegment(_ app: XCUIApplication, _ name: String) {
        let segmented = app.segmentedControls.buttons[name].firstMatch
        if segmented.waitForExistence(timeout: 1.5) { segmented.tap(); return }
        let button = app.buttons[name].firstMatch
        if button.waitForExistence(timeout: 2) { button.tap() }
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 3) { back.tap() }
        Thread.sleep(forTimeInterval: 1.2)
    }

    /// Closes an active search field (Apple shows Cancel or an X).
    private func dismissSearch(_ app: XCUIApplication) {
        for label in ["Cancel", "Close", "Clear text"] {
            let b = app.buttons[label].firstMatch
            if b.exists && b.isHittable { b.tap(); Thread.sleep(forTimeInterval: 0.6) }
            if !app.keyboards.firstMatch.exists { return }
        }
    }

    /// Goes back until the tab bar shows again, so the next tab tap lands.
    private func backToTabs(_ app: XCUIApplication) {
        for _ in 0..<6 {
            if app.tabBars.firstMatch.exists && app.tabBars.firstMatch.isHittable { return }
            if app.keyboards.firstMatch.exists { dismissSearch(app) }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists && back.isHittable { back.tap() } else { app.swipeDown(velocity: .fast) }
            Thread.sleep(forTimeInterval: 1.2)
        }
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    /// Capture the simulator's resolved Apple system font families, including the score ring's exact 25.2pt bold.
    func testSystemFontName() throws {
        let styles: [(String, UIFont.TextStyle)] = [
            ("largeTitle", .largeTitle), ("title1", .title1), ("title2", .title2),
            ("title3", .title3), ("headline", .headline), ("body", .body),
            ("callout", .callout), ("subheadline", .subheadline), ("footnote", .footnote),
            ("caption1", .caption1), ("caption2", .caption2)
        ]
        var rows: [String] = []
        for (name, style) in styles {
            let font = UIFont.preferredFont(forTextStyle: style)
            rows.append("\(name): \(font.fontName) | family=\(font.familyName) | size=\(font.pointSize)")
            XCTAssertTrue(font.fontName.contains("SF") || font.fontName.contains("System"), "Unexpected font: \(font.fontName)")
        }
        let scoreSize = UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 84 * 0.3)
        let score = UIFont.systemFont(ofSize: scoreSize, weight: .bold)
        let scoreRounded = score.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: scoreSize) }
        let scoreMono = UIFont.monospacedSystemFont(ofSize: scoreSize, weight: .bold)
        rows.append("ScoreRing actual .scaled(size:84*0.3, weight:.bold, design:nil): \(score.fontName) | family=\(score.familyName) | size=\(score.pointSize)")
        rows.append("score rounded system variant (not applied): \(scoreRounded?.fontName ?? "unavailable") | family=\(scoreRounded?.familyName ?? "unavailable")")
        rows.append("score monospaced system variant (not applied): \(scoreMono.fontName) | family=\(scoreMono.familyName)")
        XCTAssertTrue(score.fontName.contains("SF") || score.fontName.contains("System"))
        try rows.joined(separator: "\n").write(to: URL(fileURLWithPath: "\(Self.shotDir)/font-proof.txt"), atomically: true, encoding: .utf8)
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1)
        tab(app, "Insights"); tapSegment(app, "Day"); pause(1)
        shot("sf-proof-insights")
    }

    /// Font check: the real iOS Settings app next to Dayline's People and Day score pages, same simulator, same scale.
    func testFontProof() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch(); pause(2.5); shot("fp-ios-settings")
        let general = settings.staticTexts["General"].firstMatch
        if general.waitForExistence(timeout: 4) { general.tap(); pause(2); shot("fp-ios-general") }
        settings.terminate()
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1.5)
        tab(app, "Insights"); pause(1.5)
        app.buttons["Month"].firstMatch.tap(); pause(1.2)
        tapID(app, "streakCard"); pause(2)
        tapID(app, "peopleButton"); pause(2); shot("fp-people")
        app.terminate()
        app.launch(); pause(1.5)
        tab(app, "Today"); pause(1.5); tapID(app, "scoreCard"); pause(2); shot("fp-dayscore")
    }

    /// Names next to profile circles: Apple's Contacts app next to Dayline's People page.
    func testFontProofContacts() throws {
        let contacts = XCUIApplication(bundleIdentifier: "com.apple.MobileAddressBook")
        contacts.launch(); pause(3); shot("fpc-ios-contacts")
        let first = contacts.cells.firstMatch
        if first.waitForExistence(timeout: 4) { first.tap(); pause(2); shot("fpc-ios-contact") }
        contacts.terminate()
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1.5)
        tab(app, "Insights"); pause(1.5)
        app.buttons["Month"].firstMatch.tap(); pause(1.2)
        tapID(app, "streakCard"); pause(2)
        tapID(app, "peopleButton"); pause(2); shot("fpc-people")
    }

    /// People circles (Contacts-style monograms): Streak rows, People, a person, Add People.
    func testPeopleCircles() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1.5)
        tab(app, "Insights"); pause(1.5)
        app.buttons["Month"].firstMatch.tap(); pause(1.2)
        tapID(app, "streakCard"); pause(2); shot("pc1-streak")
        app.swipeDown(); pause(1); shot("pc0-streak-top")
        app.swipeUp(); pause(1.2); shot("pc1b-streak-friends"); app.swipeDown(); pause(1)
        tapID(app, "peopleButton"); pause(2); shot("pc2-people")
        app.swipeUp(); pause(1.2); shot("pc2b-people-scrolled"); app.swipeDown(); pause(1)
        tapID(app, "person-Sam"); pause(2); shot("pc3-person-sam"); goBack(app); pause(1)
        app.swipeUp(); pause(1)
        tapID(app, "addPerson"); pause(2); shot("pc4-add-people")
    }

    /// Widget design choices: each design's Home Screen page and its large + Lock Screen page.
    func testWidgetDesigns() throws {
        for n in 1...12 {
            for p in 1...2 {
                let app = XCUIApplication()
                app.launchArguments = ["-demo", "-widgetDesign", "\(n)", "-widgetPage", "\(p)"]
                app.launch(); pause(1.2)
                shot(String(format: "wd%02d-%d", n, p))
                app.terminate()
            }
        }
    }

    /// The real Today Schedule > Gym row opens the selected default Gym page.
    /// Native Schedule and icon-list captures, not image composites.
    func testOfficeStyleLists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-appearance", "light"]
        app.launch(); pause(2)
        XCTAssertTrue(app.descendants(matching: .any)["todaySchedule"].firstMatch.exists)
        shot("today-office-rows-native")
        tab(app, "Insights"); pause(1)
        shot("insights-office-factor-rows-native")
    }

    func testTodayGymNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launchEnvironment["TZ"] = Self.morningZone
        app.launch(); pause(1.5)
        let gym = app.staticTexts["Gym"].firstMatch
        XCTAssertTrue(gym.waitForExistence(timeout: 5), "Gym schedule row missing")
        shot("today-gym-row-wired")
        gym.tap(); pause(3)
        XCTAssertTrue(app.descendants(matching: .any)["gymDetail"].firstMatch.waitForExistence(timeout: 4), "Gym page did not open")
        shot("today-gym-page-opened")
    }

    /// Real Today Gym row and current default Gym page for an annotated entry-point proposal.
    /// No new navigation is added by this preview.
    func testGymEntryProposal() throws {
        let today = XCUIApplication()
        today.launchArguments = ["-demo"]
        today.launchEnvironment["TZ"] = Self.morningZone
        today.launch(); pause(1.5)
        shot("gym-proposal-real-today")
        today.terminate()

        let gym = XCUIApplication()
        gym.launchArguments = ["-demo", "-detailVariant", "1"]
        gym.launchEnvironment["TZ"] = Self.morningZone
        gym.launch(); pause(1.2)
        tapID(gym, "nextTile"); pause(5)
        XCTAssertTrue(gym.descendants(matching: .any)["gymDetail"].firstMatch.exists)
        shot("gym-proposal-current-page")
    }

    /// Steps and Gym tile pages: five options each.
    func testTileDetailOptions() throws {
        for v in 1...5 {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-detailVariant", "\(v)"]
            app.launch(); pause(1.5)
            tapID(app, "nextTile"); pause(2.5); shot("td-gym-\(v)")
            app.swipeUp(); pause(1); shot("td-gym-\(v)b")
            app.terminate()
        }
    }

    /// Three combinations of Gym's map/Next/visits and weekly checkmarks.
    func testGymCombined() throws {
        for n in 6...8 {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-detailVariant", "\(n)"]
            app.launch(); pause(1.2)
            tapID(app, "nextTile"); pause(2)
            shot("gc\(n)")
            app.terminate()
        }
    }

    /// Three subtler Next treatments on the chosen combo-7 Gym page.
    func testGymQuietNext() throws {
        for n in 9...11 {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-detailVariant", "\(n)"]
            app.launch(); pause(1.2)
            tapID(app, "nextTile"); pause(2.2)
            shot("gym-quiet-next-\(n)")
            app.terminate()
        }
    }

    /// Option 2 with three thicker ring widths in light and dark appearance.
    func testWidgetThickRings() throws {
        for n in 13...15 {
            for p in 1...2 {
                let app = XCUIApplication()
                app.launchArguments = ["-demo", "-widgetDesign", "\(n)", "-widgetPage", "\(p)"]
                app.launch(); pause(1)
                shot("wt\(n)-\(p)")
                app.terminate()
            }
        }
    }

    /// Optional new widget concepts, separate from the locked score/friends widgets.
    func testWidgetConcepts() throws {
        for n in 1...3 {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-widgetConcept", "\(n)"]
            app.launch(); pause(1)
            shot("wc\(n)")
            app.terminate()
        }
    }

    /// Sleep time pickers use compact Settings-style rows, without the old tall padding.
    func testCompactSleepRows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1)
        tab(app, "Profile"); pause(1)
        tapID(app, "yourScheduleRow"); pause(1.5)
        shot("compact-sleep-rows")
    }

    /// Verbatim, one-line Siri phrases, with Hey Siri on every row.
    func testShortSiriExamples() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1)
        tab(app, "Profile"); pause(1)
        tapID(app, "useWithSiriRow"); pause(1.3)
        shot("siri-short-phrases")
    }

    /// Work and gym pickers are directly on Your Schedule; old habits are gone.
    func testScheduleLocations() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1)
        tab(app, "Profile"); pause(0.8)
        tapID(app, "yourScheduleRow"); pause(1.3)
        app.swipeUp(); pause(0.8)
        shot("schedule-locations-and-habits")
        XCTAssertFalse(app.staticTexts["Time Outside"].exists)
        XCTAssertFalse(app.staticTexts["Get Out of the House"].exists)
        let work = app.descendants(matching: .any)["workLocation"].firstMatch
        if work.waitForExistence(timeout: 3) { work.tap(); pause(1.2); shot("schedule-work-picker") }
        goBack(app)
        let gym = app.descendants(matching: .any)["gymLocation"].firstMatch
        if gym.waitForExistence(timeout: 3) { gym.tap(); pause(1.2); shot("schedule-gym-picker") }
    }

    /// Show Symbols affects rows on Today, its schedule, Timeline, Day score, and Profile.
    func testSymbolsOnOff() throws {
        for (enabled, label) in [(true, "on"), (false, "off")] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-symbols.show", enabled ? "YES" : "NO"]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5)
            shot("symbols-\(label)-today")
            tapID(app, "scoreCard"); pause(1.5)
            shot("symbols-\(label)-schedule")
            app.swipeUp(); pause(0.8)
            shot("symbols-\(label)-factors")
            goBack(app)
            tab(app, "Timeline"); pause(2)
            shot("symbols-\(label)-timeline")
            tab(app, "Profile"); pause(1)
            shot("symbols-\(label)-profile")
            app.terminate()
        }
    }

    /// Flip the real Profile switch, then revisit Timeline and the schedule without relaunching.
    func testSymbolsToggleLive() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launchEnvironment["TZ"] = Self.morningZone
        app.launch(); pause(1)
        tab(app, "Profile"); pause(0.8)
        let toggle = app.switches["Show Symbols"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Show Symbols switch missing")
        if toggle.value as? String == "1" { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, "0", "Show Symbols must be off for this shot")
        pause(0.7); shot("symbols-switched-off-profile")
        tab(app, "Timeline"); pause(1.5); shot("symbols-switched-off-timeline")
        tab(app, "Today"); tapID(app, "scoreCard"); pause(1.3)
        shot("symbols-switched-off-schedule")
        goBack(app)
        tab(app, "Profile")
        if toggle.waitForExistence(timeout: 3) { toggle.tap() }
        pause(0.6)
        tab(app, "Timeline"); pause(1.3); shot("symbols-switched-on-timeline")
    }

    /// Three Week-at-a-glance designs, each with an orange low day in light and dark.
    func testWeekWidgetVariations() throws { try captureWeekWidgets() }
    func testWeekWidgetVariationsDark() throws { try captureWeekWidgets() }
    private func captureWeekWidgets() throws {
        for n in 21...23 {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-widgetConcept", "\(n)"]
            app.launch(); pause(1)
            shot("week-widget-\(n)")
            app.terminate()
        }
    }

    func testWeekWidgetSizeLight() throws { captureWeekWidgetSize("light") }
    func testWeekWidgetSizeDark() throws { captureWeekWidgetSize("dark") }
    private func captureWeekWidgetSize(_ appearance: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-weekWidgetSize"]
        app.launch(); pause(1)
        shot("week-widget-size-\(appearance)")
    }

    func testSearchSuggestionFill() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-searchDesign", "1", "-searchKeyboard"]
        app.launch(); tab(app, "Journal"); tapID(app, "journalSearch"); pause(1)
        app.buttons["Where was I 4 days ago?"].firstMatch.tap(); pause(1)
        shot("search-suggestion-filled")
    }

    /// Five landing options on an actual phone keyboard; live autocomplete and typo recovery.
    func testSearchDesigns() throws {
        for n in 1...5 {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-searchDesign", "\(n)", "-searchKeyboard"]
            app.launch(); pause(1.2)
            tab(app, "Journal"); pause(1)
            tapID(app, "journalSearch"); pause(1.5)
            let field = app.textFields["searchField"]
            if field.waitForExistence(timeout: 5) { field.tap(); pause(0.8) }
            shot("search-\(n)")
            if n == 1 {
                field.typeText("where was I")
                pause(1.2); shot("search-autocomplete")
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 11) + "Blue Dor Coffee")
                pause(1.2); shot("search-typo")
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 15) + "Blue Door Coffee")
                pause(1.2); shot("search-results")
            }
            app.terminate()
        }
    }

    func testSearchSubmitPhotoRows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-searchKeyboard"]
        app.launch(); tab(app, "Journal"); tapID(app, "journalSearch"); pause(1)
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("where was I 4 days ago")
        let submit = app.keyboards.buttons["search"].firstMatch
        if submit.waitForExistence(timeout: 3) { submit.tap() }
        else { field.typeText("\n") }
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2), "Search must dismiss keyboard")
        pause(5); shot("search-submit-photo-rows")
    }

    /// A place search opens its place page, then Back preserves the search results.
    func testSearchPlaceNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-journalSearch", "Blue Door Coffee"]
        app.launch(); pause(1)
        tab(app, "Journal"); pause(1)
        tapID(app, "journalSearch"); pause(1.5)
        let field = app.textFields["searchField"]
        if field.waitForExistence(timeout: 4) { field.tap(); field.typeText("Blue Door Coffee") }
        pause(1); shot("search-results-place")
        let hit = app.descendants(matching: .any)["searchHit"].firstMatch
        if hit.waitForExistence(timeout: 4) { hit.tap(); pause(2); shot("search-place-page") }
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap(); pause(1) }
        let dismiss = app.buttons["Continue"]
        if dismiss.exists { dismiss.tap(); pause(0.6) }
        shot("search-back-results")
    }

    func testPlaceFinalDefault() throws { captureFreshPlace([17]) }
    func testPlaceCombo14() throws { captureFreshPlace([14]) }
    func testPlaceCombo15() throws { captureFreshPlace([15]) }
    func testPlaceCombo16() throws { captureFreshPlace([16]) }
    func testPlaceCombo9() throws { captureFreshPlace([9]) }
    func testPlaceCombo10() throws { captureFreshPlace([10]) }
    func testPlaceCombo11() throws { captureFreshPlace([11]) }
    func testPlaceCombo12() throws { captureFreshPlace([12]) }
    func testPlaceCombo13() throws { captureFreshPlace([13]) }
    func testPlaceFreshOption6() throws { captureFreshPlace([6]) }
    func testPlaceFreshOption7() throws { captureFreshPlace([7]) }
    func testPlaceFreshOption8() throws { captureFreshPlace([8]) }
    private func captureFreshPlace(_ options: [Int]) {
        for n in options {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-journalSearch", "Blue Door Coffee", "-placeDesign", "\(n)"]
            app.launch(); tab(app, "Journal"); pause(0.5)
            tapID(app, "journalSearch"); pause(0.7)
            let field = app.textFields["searchField"]
            if field.waitForExistence(timeout: 4) { field.tap(); field.typeText("Blue Door Coffee") }
            pause(0.8)
            let hit = app.descendants(matching: .any)["searchHit"].firstMatch
            if hit.waitForExistence(timeout: 4) {
                hit.tap(); pause(4)
                XCTAssertTrue(app.descendants(matching: .any)["placeGoButton"].firstMatch.exists, "GO button missing")
                shot("place-fresh-option-\(n)")
            }
            app.terminate()
        }
    }

    func testPlaceDesigns() throws {
        for n in 1...3 {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-journalSearch", "Blue Door Coffee", "-placeDesign", "\(n)"]
            app.launch(); tab(app, "Journal"); pause(0.5)
            tapID(app, "journalSearch"); pause(0.7)
            let field = app.textFields["searchField"]
            if field.waitForExistence(timeout: 4) { field.tap(); field.typeText("Blue Door Coffee") }
            pause(0.8)
            let hit = app.descendants(matching: .any)["searchHit"].firstMatch
            if hit.waitForExistence(timeout: 4) { hit.tap(); pause(4); shot("place-design-\(n)") }
            app.terminate()
        }
    }

    /// Steps page (picked: Health-style chart), opened from the Steps tile: D and W.
    func testStepsPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1.5)
        tapID(app, "stepsTile"); pause(2); shot("sp1-day")
        tapSegment(app, "W"); pause(1.5); shot("sp2-week")
    }

    /// Today tiles (just the number, Next named as the thing) and the Day score calendar (Apple Calendar circle).
    func testTodayTilesCalendar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1.5)
        shot("tc1-today")
        tapID(app, "scoreCard"); pause(2)
        tapID(app, "dayTitle"); pause(2); shot("tc2-calendar")
    }

    /// Steps in the Day score ring's style: five layouts, and the ring opens the Steps page.
    func testDayPickerGlassDark() { pickerGlass("Dark") }
    func testDayPickerGlassLight() { pickerGlass("Light") }

    private func pickerGlass(_ scheme: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-appearance", scheme.lowercased()]
        app.launch(); pause(1)
        tapID(app, "scoreCard"); pause(1)
        tapID(app, "dayTitle"); pause(1)
        XCTAssertTrue(app.descendants(matching: .any)["dayPicker"].firstMatch.exists)
        shot("day-picker-glass-\(scheme.lowercased())")
    }

    func testStepsRing() throws {
        for n in 1...5 {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-stepsRing", "\(n)"]
            app.launch(); pause(1.5)
            shot("sr\(n)")
            if n == 1 { tapID(app, "stepsTile"); pause(2); shot("sr1-open") }
            app.terminate()
        }
    }

    /// Day Score, Steps, Friends is the selected Today order; Next stays absent.
    func testTodayScoreStepsFriendsNoNext() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1.5)
        XCTAssertTrue(app.descendants(matching: .any)["friendsCircleCard"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["nextTile"].firstMatch.exists)
        shot("today-score-steps-friends")
    }

    /// Picked Friends card on Today and full Streak page on tap.
    func testFriendsCircleCard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1.5)
        shot("fc1-today")
        tapID(app, "friendsCircleCard"); pause(2)
        shot("fc2-open")
    }

    /// Five ways to reach streak and friends faster.
    func testFriendsEntry() throws {
        for n in 1...5 {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-friendsEntry", "\(n)"]
            app.launch(); pause(1.5)
            if n == 1 {
                shot("fe1-today")
                tab(app, "Friends"); pause(2); shot("fe1-tab")
            } else if n == 5 {
                tab(app, "Insights"); pause(2); shot("fe5-insights")
            } else {
                if n == 2 { app.swipeUp(); pause(1) }
                shot("fe\(n)-today")
                tapID(app, "friendsEntry"); pause(2); shot("fe\(n)-open")
            }
            app.terminate()
        }
    }

    /// Dismiss iOS's one-time swipe-keyboard lesson before judging the app's audio controls.
    /// Depending on simulator version, the tutorial belongs to the app or SpringBoard.
    private func clearKeyboardLesson(_ app: XCUIApplication) {
        let spring = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<10 {
            let candidates = [spring.buttons["Continue"].firstMatch, app.buttons["Continue"].firstMatch]
            if let button = candidates.first(where: { $0.exists && $0.isHittable }) {
                button.tap(); pause(0.5)
            }
            pause(0.25)
        }
        XCTAssertFalse(spring.buttons["Continue"].firstMatch.exists, "Keyboard lesson still covers the editor")
        XCTAssertFalse(app.buttons["Continue"].firstMatch.exists, "Keyboard lesson still covers the editor")
    }

    /// New Entry's clean microphone composer, with the keyboard visible.
    func testJournalAudioBar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1)
        tab(app, "Journal"); pause(1)
        tapID(app, "newEntry"); pause(1.3)
        clearKeyboardLesson(app)
        XCTAssertTrue(app.descendants(matching: .any)["voiceMic"].firstMatch.exists)
        shot("journal-mic-composer")
    }

    /// Capture the short-tap hint and return to the balanced two-circle composer.
    func testJournalAudioTapHintVideo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1)
        tab(app, "Journal"); pause(1)
        tapID(app, "newEntry"); pause(1)
        clearKeyboardLesson(app)
        let mic = app.descendants(matching: .any)["voiceMic"].firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 4))
        shot("journal-mic-circles-before")
        mic.tap(); pause(0.2)
        XCTAssertTrue(app.descendants(matching: .any)["voiceHoldHint"].firstMatch.exists)
        shot("journal-mic-short-tap-hint")
        pause(1.8)
        XCTAssertFalse(app.descendants(matching: .any)["voiceHoldHint"].firstMatch.exists)
        shot("journal-mic-hint-collapsed")
        mic.press(forDuration: 3.0)
        pause(0.5)
        XCTAssertTrue(app.descendants(matching: .any)["audioHoldBar"].firstMatch.exists)
        shot("journal-mic-recording-red")
        tapID(app, "voiceStop"); pause(0.4)
        let send = app.buttons["voiceSend"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 3), "Release should show a send button")
        shot("journal-mic-ready-to-send")
        send.tap(); pause(1)
        shot("journal-mic-sent-collapsed")
    }

    /// Hold the microphone, then release to attach or slide away to cancel.
    func testJournalAudioBarRecording() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1)
        tab(app, "Journal"); pause(1)
        tapID(app, "newEntry"); pause(1)
        clearKeyboardLesson(app)
        let mic = app.descendants(matching: .any)["voiceMic"].firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 4))
        mic.press(forDuration: 1.2)
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 3) {
            allow.tap(); pause(0.7)
            mic.press(forDuration: 1.2)
        }
        pause(1.5)
        shot("journal-voice-recording-red")
        tapID(app, "voiceStop"); pause(0.5)
        shot("journal-voice-ready-blue")
    }

    /// Day/Week/Month/Year: press and slide across the switcher (recorded as video).
    func testSegmentedVideo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1.5)
        tab(app, "Timeline"); pause(2.5)
        let seg = app.segmentedControls.firstMatch
        guard seg.waitForExistence(timeout: 3) else { shot("sv-missing"); return }
        shot("sv1-timeline")
        let day = seg.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
        let year = seg.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))
        let week = seg.coordinate(withNormalizedOffset: CGVector(dx: 0.37, dy: 0.5))
        day.press(forDuration: 0.4, thenDragTo: year, withVelocity: .slow, thenHoldForDuration: 0.6); pause(1.5)
        year.press(forDuration: 0.3, thenDragTo: day, withVelocity: .default, thenHoldForDuration: 0.4); pause(1.5)
        week.tap(); pause(1.2)
        seg.coordinate(withNormalizedOffset: CGVector(dx: 0.63, dy: 0.5)).tap(); pause(1.2)
        shot("sv2-month")
        tab(app, "Insights"); pause(2)
        let seg2 = app.segmentedControls.firstMatch
        if seg2.waitForExistence(timeout: 3) {
            seg2.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.4, thenDragTo: seg2.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.6)
            pause(1.5); shot("sv3-insights")
        }
        pause(1)
    }

    /// Day score breakdown: orange symbol on rows that took points away; circles vs bare symbols.
    func testFactorIcons() throws {
        for style in ["circle", "bare"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-factorIcons", style]
            app.launch(); pause(1.5)
            tapID(app, "scoreCard"); pause(2)
            app.swipeUp(); pause(1.2); shot("fi-\(style)")
            app.terminate()
        }
    }

    /// Find My inspired frosted factor-list options, in light and dark mode.
    func testFactorGlass() throws { factorGlassShots("light") }
    func testFactorGlassDark() throws { factorGlassShots("dark") }
    private func factorGlassShots(_ mode: String) {
        for n in 1...3 {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-factorGlass", "\(n)"]
            app.launch(); pause(1.2)
            tapID(app, "scoreCard"); pause(1.8)
            app.swipeUp(); pause(1)
            shot("fg\(n)-\(mode)")
            app.terminate()
        }
    }

    func testSplashCurrentLight() throws { captureSplashCurrent("light") }
    func testSplashCurrentDark() throws { captureSplashCurrent("dark") }
    private func captureSplashCurrent(_ appearance: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-onboarding", "-splash.map", "loop"]
        app.launch(); pause(10)
        shot("splash-current-\(appearance)")
    }

    /// Light and dark app appearances should drive Apple's live map colors.
    func testAppMapAppearanceLight() throws { captureAppMapAppearance("light") }
    func testAppMapAppearanceDark() throws { captureAppMapAppearance("dark") }
    private func captureAppMapAppearance(_ appearance: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-appearance", appearance]
        app.launch(); pause(1)
        tab(app, "Timeline"); pause(8)
        shot("app-map-timeline-\(appearance)")
        tab(app, "Profile"); pause(1)
        tapID(app, "yourScheduleRow"); pause(1)
        shot("app-map-schedule-\(appearance)")
    }

    /// Live splash and Timeline tiles honor the dark app appearance.
    func testAllMapsDark() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-onboarding", "-splash.map", "loop"]
        app.launch(); pause(3)
        shot("dark-map-splash")
        app.terminate()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1)
        tab(app, "Timeline"); pause(3)
        shot("dark-map-timeline")
    }

    /// The chosen wallpaper is the same in the app and the widget preview.
    func testWidgetBackgroundMatch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-background", "sunset"]
        app.launch(); pause(1.3)
        shot("wallpaper-sunset-app")
        app.terminate()
        app.launchArguments = ["-demo", "-background", "sunset", "-widgetDesign", "14", "-widgetPage", "1", "-widgetSync"]
        app.launch(); pause(1.2)
        shot("wallpaper-sunset-widget")
    }

    /// Opt-in toggle is off by default and can be switched on from the picker.
    func testWidgetSyncToggle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-background", "sunset"]
        app.launch(); pause(1)
        tab(app, "Profile"); pause(0.8)
        tapID(app, "backgroundRow"); pause(1)
        app.swipeUp(); pause(0.5)
        shot("widget-sync-off")
        let toggle = app.switches["Sync widget"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Sync widget switch missing")
        if toggle.value as? String == "0" { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, "1", "Sync widget must be on for this shot")
        pause(0.6); shot("widget-sync-on")
    }

    /// Four genuinely different icon treatments on the same Day score factor rows.
    func testFactorIconStyles() throws {
        for n in 1...4 {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-factorIconStyle", "\(n)"]
            app.launch(); pause(1.2)
            tapID(app, "scoreCard"); pause(1.5)
            app.swipeUp(); pause(0.8)
            shot("factor-icon-style-\(n)")
            app.terminate()
        }
    }

    /// Full map: panel 8pt from the screen edges, Maps logo just above it.
    func testFullMapEdges() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1.5)
        tab(app, "Timeline"); pause(3)
        let card = app.descendants(matching: .any)["mapCard"].firstMatch
        if card.waitForExistence(timeout: 3) { card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap() }
        pause(2.5); shot("fm1-day")
        tapSegment(app, "Week"); pause(2.5); shot("fm2-week")
        // Every layer off -> clean map.
        let grabber = app.descendants(matching: .any)["mapGrabber"].firstMatch
        if grabber.waitForExistence(timeout: 2) { grabber.tap(); pause(1.5) }
        shot("fm3-layers")
        for name in ["Journal", "Photos", "Route", "Places"] {
            let toggle = app.switches[name].firstMatch
            if toggle.waitForExistence(timeout: 2) { toggle.tap(); pause(0.4) }
        }
        if grabber.exists { grabber.tap(); pause(1.5) }
        shot("fm4-all-off")
    }

    /// Timeline photo cards open their entry.
    func testTimelinePhotoOpens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1.5)
        tab(app, "Timeline"); pause(3)
        shot("tp0-timeline")
        let photos = app.descendants(matching: .any).matching(identifier: "timelinePhoto")
        if photos.count > 1 { photos.element(boundBy: 1).tap(); pause(2); shot("tp2-second") ; app.navigationBars.buttons.element(boundBy: 0).tap(); pause(1.5) }
        if photos.firstMatch.waitForExistence(timeout: 3) { photos.firstMatch.tap(); pause(2); shot("tp1-first") }
    }

    /// Tapping a photo or journal pin on the full map opens that entry.
    func testMapPinOpens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1.5)
        tab(app, "Timeline"); pause(3)
        let card = app.descendants(matching: .any)["mapCard"].firstMatch
        if card.waitForExistence(timeout: 3) { card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap() }
        pause(2.5)
        let photo = app.descendants(matching: .any)["mapPhotoPin"].firstMatch
        if photo.waitForExistence(timeout: 3) { photo.tap(); pause(2); shot("mp1-photo")
            let close = app.buttons["closeEntry"].firstMatch
            if close.exists { close.tap(); pause(1.5) }
        }
        let note = app.descendants(matching: .any)["mapJournalPin"].firstMatch
        if note.waitForExistence(timeout: 3) { note.tap(); pause(2); shot("mp2-journal") }
    }

    /// White background: should look like Settings (light gray page, white cards).
    func testWhiteBackground() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-background", "white"]
        app.launch(); pause(1.5)
        tab(app, "Profile"); pause(1.5); shot("wb1-profile")
        tab(app, "Today"); pause(1.5); shot("wb2-today")
        tab(app, "Timeline"); pause(2.5); shot("wb3-timeline")
        tab(app, "Insights"); pause(1.5); shot("wb4-insights")
        tab(app, "Journal"); pause(1.5); shot("wb5-journal")
    }

    /// Dark-mode surface hierarchy: black canvas, lighter grouped cards across five tabs.
    func testInsightsDayDark() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        tab(app, "Insights")
        tapSegment(app, "Day")
        pause(1.5)
        shot("insights-day-dark")
    }

    func testDarkSurfacesDark() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1)
        for (tabName, shotName) in [("Today", "dk1-today"), ("Timeline", "dk2-timeline"),
                                    ("Insights", "dk3-insights"), ("Journal", "dk4-journal"),
                                    ("Profile", "dk5-profile")] {
            tab(app, tabName); pause(1.3); shot(shotName)
        }
    }

    /// Bottom edge check (dark): each main page scrolled to the end, so the last card should run to the screen edge.
    func testBottomEdgesDark() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch(); pause(1.5)
        func toEnd(_ name: String) { for _ in 0..<5 { app.swipeUp(); pause(0.4) }; pause(1); shot(name) }
        tab(app, "Today"); pause(1.5); toEnd("be1-today")
        app.swipeDown(); app.swipeDown(); pause(1)
        tapID(app, "scoreCard"); pause(2); toEnd("be2-day-score"); app.swipeDown(); pause(0.6); shot("be2b-day-score-mid")
        app.swipeRight(); pause(1.5); shot("be2c-day-score-yesterday"); goBack(app); pause(1)
        tab(app, "Timeline"); pause(2.5); toEnd("be3-timeline")
        tab(app, "Insights"); pause(1.5); toEnd("be4-insights")
        tab(app, "Journal"); pause(1.5); toEnd("be5-journal")
        tab(app, "Profile"); pause(1.5); toEnd("be6-profile")
    }

    /// Anything good wins points back: a run from Apple Health and lots of steps, on the ring and in the day story.
    func testMakeUpRun() throws {
        for (name, hour) in [("mu-1-10am", 10), ("mu-2-4pm", 16), ("mu-3-8pm", 20)] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-demo.pace", "run", "-status.phrase", "1"]
            app.launchEnvironment["TZ"] = Self.zone(localHour: hour)
            app.launch(); pause(2.5); shot(name)
            app.terminate()
        }
    }
}
