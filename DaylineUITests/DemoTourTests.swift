import XCTest

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

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: Self.shotDir, withIntermediateDirectories: true)
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
        tapID(app, "permissionsContinue"); pause(1.2); shot("06c-permissions-mic")
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

    /// Siri row icon options (preview only).
    func testSiriIcons() {
        for (style, name) in [("waveform", "c9-siri-now"), ("orb", "c9b-siri-orb"), ("circle", "c9c-siri-circle")] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-siri.iconStyle", style]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch()
            tab(app, "Profile"); pause(1.5)
            let row = app.descendants(matching: .any)["useWithSiriRow"].firstMatch
            if !row.waitForExistence(timeout: 3) { app.swipeUp(); pause(1) }
            tapID(app, "useWithSiriRow"); pause(1.8); shot(name)
            app.terminate()
        }
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

        do {
            app = XCUIApplication()
            app.launchArguments = ["-demo"]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch()
            tab(app, "Insights"); pause(1.5); app.buttons["Day"].firstMatch.tap(); pause(1.5); shot("c13-insights-day-now")
            app.terminate()
            app = XCUIApplication()
            app.launchArguments = ["-demo"]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch()
            tab(app, "Insights"); pause(1.5)
            app.buttons["Month"].firstMatch.tap(); pause(1.2)
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Streak'")).firstMatch.tap(); pause(2)
            let hist = app.descendants(matching: .any)["streakHistory"].firstMatch
            if hist.waitForExistence(timeout: 3) { hist.swipeUp(); pause(1) }
            let d = Calendar.current.component(.day, from: Calendar.current.date(byAdding: .day, value: -3, to: .now)!)
            let cell = app.descendants(matching: .any)["historyDay-\(d)"].firstMatch
            if cell.waitForExistence(timeout: 3) { cell.tap(); pause(2); shot("c15-streak-day") }
            app.terminate()
            app = XCUIApplication()
            app.launchArguments = ["-demo", "-insights.simpleDay", "YES"]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch()
            tab(app, "Insights"); pause(1.5); app.buttons["Day"].firstMatch.tap(); pause(1.5); shot("c14-insights-day-proposed")
            app.terminate()
        }
        do {
            app = XCUIApplication()
            app.launchArguments = ["-demo", "-rings.thick", "YES"]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch()
            tab(app, "Today"); pause(2); shot("c18a-today-thick")
            tapID(app, "scoreCard"); pause(2); shot("c18b-dayscore-thick"); goBack(app)
            tab(app, "Insights"); pause(1.5); app.buttons["Month"].firstMatch.tap(); pause(1.2)
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Streak'")).firstMatch.tap(); pause(2); shot("c18c-streak-thick")
            app.terminate()
        }
        for letter in ["now", "B", "C"] {
            app = XCUIApplication()
            app.launchArguments = ["-demo", "-chrome.style", letter, "-yourData.style", "A"]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch()
            tab(app, "Profile"); pause(1.5)
            tapID(app, "accountRow"); pause(1.5); shot("c25\(letter)-back-button"); goBack(app); pause(1)
            tapID(app, "yourDataRow"); pause(1.5); tapID(app, "deleteAccount"); pause(1.2); shot("c25\(letter)x-alert")
            app.terminate()
        }
        for letter in ["A", "B", "C"] {
            app = XCUIApplication()
            app.launchArguments = ["-demo", "-notifications.style", letter]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch()
            tab(app, "Profile"); pause(1.5)
            tapID(app, "notificationsRow"); pause(1.8); shot("c24\(letter)-notifications")
            app.terminate()
        }
        for letter in ["A", "B", "C"] {
            app = XCUIApplication()
            app.launchArguments = ["-demo", "-yourData.style", letter]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch()
            tab(app, "Profile"); pause(1.5)
            tapID(app, "yourDataRow"); pause(1.8); shot("c23\(letter)-your-data")
            tapID(app, "deleteAccount"); pause(1.2); shot("c23\(letter)x-your-data-confirm")
            app.terminate()
        }
        for letter in ["A", "B", "C"] {
            app = XCUIApplication()
            app.launchArguments = ["-demo", "-journal.cardStyle", letter]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch()
            tab(app, "Journal"); pause(2); shot("c22\(letter)-journal-card")
            app.terminate()
        }
        for (style, letter) in [("circle", "A"), ("square", "B"), ("outlined", "C")] {
            app = XCUIApplication()
            app.launchArguments = ["-demo", "-icons.markerStyle", style]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch()
            tab(app, "Timeline"); pause(3); shot("c16\(letter)-pins-\(style)")
            tab(app, "Insights"); pause(1.5); app.buttons["Month"].firstMatch.tap(); pause(1.2)
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Streak'")).firstMatch.tap(); pause(2)
            if style == "circle" { shot("c17-streak-now") }
            app.swipeUp(); pause(0.8); app.swipeUp(); pause(1.2); shot("c17\(letter)-people-\(style)")
            app.terminate()
        }
        for (bg, extra, name) in [("system", [String](), "c4-profile"), ("black", [], "c5-profile-black"), ("white", [], "c6-profile-white-now"), ("white", ["-background.whiteGrouped", "YES"], "c7-profile-white-proposed")] {
            app = XCUIApplication()
            app.launchArguments = ["-demo", "-background.preset", bg] + extra
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch()
            tab(app, "Profile"); pause(2); shot(name)
            app.swipeUp(); pause(1.2); shot(name + "-scrolled")
            if bg == "system" {
                app.swipeDown(); pause(1)
                tapID(app, "accountRow"); pause(1.8); shot("c4b-account")
                goBack(app); pause(1)
                tapID(app, "yourDataRow"); pause(1.8); shot("c4c-your-data")
                goBack(app)
                tab(app, "Journal"); pause(2); shot("c19-journal")
                let jc = app.buttons["journalCard"].firstMatch
                if jc.waitForExistence(timeout: 3) { jc.tap(); pause(2); shot("c19b-journal-edit"); app.buttons["Close"].firstMatch.tap(); pause(1.2) }
                tapID(app, "newEntry"); pause(1.5)
                let mic = app.descendants(matching: .any)["voiceMic"].firstMatch
                if mic.waitForExistence(timeout: 3) { mic.tap(); pause(0.6); shot("c21-tap-hold-hint") }
                app.buttons["Close"].firstMatch.tap(); pause(1)
                if app.buttons["Discard Entry"].exists { app.buttons["Discard Entry"].tap(); pause(1) }
                tab(app, "Insights"); pause(1.5); shot("c20-insights-month")
                tab(app, "Today"); pause(2); shot("c10a-today-ring"); tapID(app, "scoreCard"); pause(2); shot("c10b-day-score"); app.swipeUp(); pause(1.2); shot("c10-factor-tiles")
                goBack(app)
                tab(app, "Timeline"); pause(3); shot("c11-timeline-tiles")
                app.swipeUp(); pause(1.2); shot("c11b-timeline-voice")
                let office = app.descendants(matching: .any)["stop-Office"].firstMatch
                if office.waitForExistence(timeout: 3) { office.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap(); pause(2); shot("c12-journal-entry"); goBack(app) }
                app.swipeDown(); pause(1)
                let card = app.descendants(matching: .any)["mapCard"].firstMatch
                if card.waitForExistence(timeout: 3) { card.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap() }
                pause(2.5); shot("c8-full-map")
            }
            app.terminate()
        }
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
        app.swipeRight(); pause(1.5); tapID(app, "previousDay"); pause(1.5); shot("16-day-score-past")
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
            // Voice note: touch and hold the mic, slide up to lock, then stop and add it.
            let mic = app.descendants(matching: .any).matching(identifier: "voiceMic").firstMatch
            if mic.waitForExistence(timeout: 2) {
                let start = mic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(forDuration: 0.6, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -120)))
                let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
                if allow.waitForExistence(timeout: 1.5) {
                    allow.tap(); pause(0.5)
                    start.press(forDuration: 0.6, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -120)))
                }
                pause(2.5); shot("51b-voice-recording-locked")
                let stop = app.buttons["Stop recording"].firstMatch
                if stop.waitForExistence(timeout: 2) { stop.tap() }
                pause(1); shot("51c-voice-review")
                let send = app.descendants(matching: .any).matching(identifier: "voiceSend").firstMatch
                if send.waitForExistence(timeout: 2) { send.tap() }
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
        if policy.waitForExistence(timeout: 3) { policy.tap() } else { tapID(app, "privacyPolicyLink") }
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

    /// Round-3 options for David (Sep 24): Insights Day A/B/C, icon tiles, Notifications B1/B2/B3.
    func testOptionScreens() throws {
        func launch(_ args: [String]) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-demo"] + args
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5); return app
        }
        for v in ["A", "B", "C"] {
            let app = launch(["-insights.dayStyle", v])
            tab(app, "Insights"); pause(1.5); tapSegment(app, "Day"); pause(2); shot("o1\(v)-insights-day")
            app.terminate()
        }
        for v in ["A", "A2", "A3", "C", "C2"] {
            let app = launch(["-icons.tile", v])
            tab(app, "Today"); pause(1.5); tapID(app, "scoreCard"); pause(2)
            app.swipeUp(); pause(1); shot("o2\(v)-icons")
            app.terminate()
        }
        for v in ["B1", "B2", "B3"] {
            let app = launch(["-notifications.style", v])
            tab(app, "Profile"); pause(1.5)
            let row = app.descendants(matching: .any)["notificationsRow"].firstMatch
            if !row.waitForExistence(timeout: 2) { app.swipeUp(); pause(1) }
            tapID(app, "notificationsRow"); pause(2); shot("o3\(v)-notifications")
            app.terminate()
        }
        do {
            let app = launch([])
            tab(app, "Timeline"); pause(2); shot("o4-timeline")
            tab(app, "Journal"); pause(2); shot("o4-journal")
            tapID(app, "newEntry"); pause(2)
            let mic = app.descendants(matching: .any)["voiceMic"].firstMatch
            shot("o5-editor"); if mic.waitForExistence(timeout: 3) { mic.tap(); pause(0.5); shot("o5-mic-quick-tap") }
            let cancel = app.navigationBars.buttons.element(boundBy: 0); if cancel.waitForExistence(timeout: 2) { cancel.tap() }; pause(1.2)
            tab(app, "Profile"); pause(2); shot("o4-profile")
            app.terminate()
        }
    }

    /// Profile rows demo for David: A = colored tiles, blue = bold blue symbols with no tile.
    func testProfileDemo() throws {
        for v in ["A", "blue"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-profile.tile", v]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5)
            tab(app, "Profile"); pause(2); shot("p\(v)-profile-top")
            app.swipeUp(); pause(1.5); shot("p\(v)-profile-rows")
            app.terminate()
        }
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

    /// Timeline "Most visited" icon options for David: A none, B blue symbol, C round tint. Week, Month, Year each.
    func testVisitedDemo() throws {
        for v in ["A", "B", "C"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-visited.icon", v]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5)
            tab(app, "Timeline"); pause(2)
            for seg in ["Week", "Month", "Year"] {
                tapSegment(app, seg); pause(2.5)
                app.swipeUp(); pause(1.5); shot("v\(v)-\(seg.lowercased())")
                app.swipeDown(); pause(1.2)
            }
            app.terminate()
        }
    }

    /// "Show Symbols" preview: Profile toggle, then every screen with bare symbols, on (C) and off (A).
    func testSymbolsDemo() throws {
        for on in ["YES", "NO"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-symbols.preview", "YES", "-symbols.show", on]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5)
            tab(app, "Profile"); pause(1.5)
            let t = app.descendants(matching: .any)["showSymbolsToggle"].firstMatch
            for _ in 0..<4 where !(t.exists && t.isHittable) { app.swipeUp(); pause(1) }
            pause(1); shot("sy\(on)-settings")
            tab(app, "Today"); pause(1.5); tapID(app, "scoreCard"); pause(2); shot("sy\(on)-dayscore")
            app.swipeUp(); pause(1.2); shot("sy\(on)-dayscore-2"); goBack(app)
            tab(app, "Timeline"); pause(2)
            for seg in ["Week", "Month", "Year"] {
                tapSegment(app, seg); pause(2.5)
                app.swipeUp(); pause(1.5); shot("sy\(on)-\(seg.lowercased())")
                app.swipeDown(); pause(1.2)
            }
            app.terminate()
        }
    }

    /// Settings look preview: section titles vs none, blue vs gray helper text, light and dark.
    func testSettingsLookDemo() throws {
        for mode in ["Light", "Dark"] {
            for v in ["old", "new"] {
                let on = v == "new" ? "YES" : "NO"
                let app = XCUIApplication()
                app.launchArguments = ["-demo", "-appearance", mode, "-settings.noHeaders", on, "-text.gray", on]
                app.launchEnvironment["TZ"] = Self.morningZone
                app.launch(); pause(1.5)
                tab(app, "Profile"); pause(2); shot("sl\(v)\(mode)-top")
                app.swipeUp(); pause(1.5); shot("sl\(v)\(mode)-rows")
                tab(app, "Timeline"); pause(2); tapSegment(app, "Week"); pause(2.5)
                app.swipeUp(); pause(1.5); shot("sl\(v)\(mode)-week")
                app.terminate()
            }
        }
    }

    /// Profile "Use with Siri" row: waveform tile now vs the Siri mark David picked.
    func testSiriProfileDemo() throws {
        for on in ["NO", "YES"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-profile.siriMark", on]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5)
            tab(app, "Profile"); pause(1.5)
            let row = app.descendants(matching: .any)["useWithSiriRow"].firstMatch
            for _ in 0..<4 where !(row.exists && row.isHittable) { app.swipeUp(); pause(1) }
            pause(1); shot("sm\(on)-profile-siri")
            app.terminate()
        }
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

    /// Segment pill: now (glass pill) vs flat gray at rest, and the glass look while it moves.
    func testPillDemo() throws {
        for (name, args) in [("now", ["-pill.style", "gray"]), ("flat", ["-pill.style", "flat"]), ("moving", ["-pill.style", "flat", "-pill.forceMoving", "YES"])] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo"] + args
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5)
            tab(app, "Timeline"); pause(2); tapSegment(app, "Week"); pause(2.5); shot("pl-\(name)")
            app.terminate()
        }
    }

    /// Week pill jelly stretch (pill.jelly A/B/C), frozen mid-slide: stretched wide, then squished narrow.
    func testJellyDemo() throws {
        for v in ["A", "B", "C"] {
            for (tag, st) in [("wide", "1"), ("narrow", "-0.6")] {
                let app = XCUIApplication()
                app.launchArguments = ["-demo", "-pill.style", "flat", "-pill.jelly", v, "-pill.forceMoving", "YES", "-pill.forceStretch", st]
                app.launchEnvironment["TZ"] = Self.morningZone
                app.launch(); pause(1.5)
                tab(app, "Timeline"); pause(2); tapSegment(app, "Month"); pause(2); shot("jl-\(v)-\(tag)")
                app.terminate()
            }
        }
    }

    /// Video: fast taps and drags across the Week pill with pill.jelly B (the workflow records the screen for *Video tests).
    func testJellyVideo() throws {
        for v in ["A", "B", "C"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-pill.style", "flat", "-pill.jelly", v]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5)
            tab(app, "Timeline"); pause(1.5)
            for seg in ["Year", "Day", "Month", "Week", "Year", "Day"] { tapSegment(app, seg); pause(0.9) }
            app.terminate()
        }
    }

    /// Video: Apple's own segmented control (pill.native) on the Timeline: taps, fast drags, and drags past the ends.
    func testNativePillVideo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-pill.native", "YES"]
        app.launchEnvironment["TZ"] = Self.morningZone
        app.launch(); pause(1.5)
        tab(app, "Timeline"); pause(1.5)
        let seg = app.segmentedControls.firstMatch
        guard seg.waitForExistence(timeout: 5) else { return }
        pause(1)
        shot("np-rest")
        for s in ["Year", "Day", "Month", "Week"] { seg.buttons[s].tap(); pause(1.0) }
        let l = seg.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
        let r = seg.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))
        let farR = seg.coordinate(withNormalizedOffset: CGVector(dx: 1.25, dy: 0.5))
        let farL = seg.coordinate(withNormalizedOffset: CGVector(dx: -0.25, dy: 0.5))
        l.press(forDuration: 0.3, thenDragTo: r, withVelocity: .fast, thenHoldForDuration: 0.3); pause(1.2)
        r.press(forDuration: 0.3, thenDragTo: l, withVelocity: .fast, thenHoldForDuration: 0.3); pause(1.2)
        l.press(forDuration: 0.3, thenDragTo: farR, withVelocity: .default, thenHoldForDuration: 0.6); pause(1.2)
        r.press(forDuration: 0.3, thenDragTo: farL, withVelocity: .default, thenHoldForDuration: 0.6); pause(1.5)
        app.terminate()
    }

    /// Big map side buttons: unselected gray (now) vs black (toggle.black), with Photos + Journal turned off.
    func testToggleDemo() throws {
        for v in ["NO", "YES"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-toggle.black", v]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5)
            tab(app, "Timeline"); pause(3)
            tapID(app, "mapCard"); pause(4)
            tapID(app, "togglePhotos"); pause(0.6); tapID(app, "toggleJournal"); pause(2)
            shot("tg-\(v)")
            app.terminate()
        }
    }

    /// Big map pull-up sheet (map.sheet A/B/C): collapsed bar with grabber, then pulled up with the three switches.
    func testMapSheetDemo() throws {
        for v in ["A", "B", "C"] {
            for open in ["NO", "YES"] {
                let app = XCUIApplication()
                app.launchArguments = ["-demo", "-route.style", "snap", "-pin.style", "D", "-map.sheet", v, "-map.sheetOpen", open]
                app.launchEnvironment["TZ"] = Self.morningZone
                app.launch(); pause(1.5)
                tab(app, "Timeline"); pause(3)
                tapID(app, "mapCard"); pause(6); shot("ms-\(v)-\(open == "YES" ? "open" : "closed")")
                app.terminate()
            }
        }
    }

    /// Privacy Policy as a row in the Your data group (no footer), light and dark.
    func testPrivacyRowDemo() throws {
        for mode in ["Light", "Dark"] {
            for on in ["NO", "YES"] {
                let app = XCUIApplication()
                app.launchArguments = ["-demo", "-appearance", mode, "-privacy.row", on]
                app.launchEnvironment["TZ"] = Self.morningZone
                app.launch(); pause(1.5)
                tab(app, "Profile"); pause(1.5)
                for _ in 0..<3 { app.swipeUp(); pause(0.8) }
                pause(1); shot("pr\(on)\(mode)")
                app.terminate()
            }
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
    func testSignInMarkDemo() throws {
        for v in ["icon", "blue", "ink", "sky", "duo"] {
            let app = XCUIApplication()
            var args = ["-demo", "-onboarding", "-signin.small", "YES"]
            args += ["-mark.rings", v == "icon" ? "" : v]
            app.launchArguments = args
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5)
            tapID(app, "splashContinue"); pause(1.8); shot("mk-\(v)-signin")
            if v == "icon" || v == "blue" {
                tapID(app, "signInOption-Google"); pause(0.8); shot("mk-\(v)-google")
                tapID(app, "signInOption-Apple"); pause(0.5)
                tapID(app, "signInContinue"); pause(1.8); shot("mk-\(v)-apple")
            }
            app.terminate()
        }
    }

    /// Full-screen Timeline map: flat vs tilted 3D (preview flag map.3d), street-following route.
    func testMap3DDemo() throws {
        for v in ["NO", "YES"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-route.style", "gps", "-map.3d", v]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5)
            tab(app, "Timeline"); pause(3)
            tapID(app, "mapCard"); pause(8); shot("m3-\(v)")
            if v == "YES" { app.swipeLeft(); pause(4); shot("m3-YES-turned") }
            app.terminate()
        }
    }

    /// Apple-style map pins: current vs A big with dot vs B compact vs C native marker, on the full-screen map.
    func testPinDemo() throws {
        for v in ["now", "A", "B", "C"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-route.style", "gps", "-pin.style", v == "now" ? "" : v]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5)
            tab(app, "Timeline"); pause(3)
            tapID(app, "mapCard"); pause(7); shot("pin-\(v)")
            app.terminate()
        }
    }

    /// David 1:56-1:57 round: new pin (A shape, small, theme blue, dot) on the big map flat and 3D (3D via the location button).
    func testPinDMapDemo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-route.style", "snap", "-pin.style", "D", "-map.3d", "YES"]
        app.launchEnvironment["TZ"] = Self.morningZone
        app.launch(); pause(1.5)
        tab(app, "Timeline"); pause(3)
        tapID(app, "mapCard"); pause(7); shot("pd-flat")
        tapID(app, "locateMe"); pause(7); shot("pd-3d")
        app.terminate()
    }

    /// David 2:15: 2D/3D button on top of the location button (one glass capsule), pull-up sheet instead of floating buttons,
    /// then map gestures: one-finger pan, pinch zoom, two-finger rotate.
    func testMapButtonsVideo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-route.style", "snap", "-pin.style", "D", "-map.3d", "YES", "-map.sheet", "A"]
        app.launchEnvironment["TZ"] = Self.morningZone
        app.launch(); pause(1.5)
        tab(app, "Timeline"); pause(3)
        tapID(app, "mapCard"); pause(6); shot("mb-flat")
        tapID(app, "toggle3D"); pause(6); shot("mb-3d")
        let map = app.maps.firstMatch
        map.swipeLeft(); pause(1.5)
        map.pinch(withScale: 2.0, velocity: 1.0); pause(2)
        map.rotate(0.8, withVelocity: 1.0); pause(2)
        map.pinch(withScale: 0.5, velocity: -1.0); pause(2)
        tapID(app, "toggle3D"); pause(4)
        tapID(app, "locateMe"); pause(4); shot("mb-locate")
        tapID(app, "mapGrabber"); pause(3); shot("mb-sheet")
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

    /// Check Location with route previews per rate: A left thumbs, B big previews on top, C right thumbs; B enlarged.
    func testCheckPreviewDemo() throws {
        for v in ["A", "B", "C"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-check.preview", v]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5)
            tab(app, "Profile"); pause(1.5)
            let row = app.staticTexts["Check Location"].firstMatch
            if !row.isHittable { app.swipeUp(); pause(0.8) }
            row.tap(); pause(5); shot("ck-\(v)")
            if v == "B" { tapID(app, "thumb-10"); pause(5); shot("ck-B-big") }
            app.terminate()
        }
    }

    /// Timeline Day map route: now vs snapped to streets vs precise GPS track.
    func testRouteDemo() throws {
        for v in ["now", "snap", "gps"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-route.style", v]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.5)
            tab(app, "Timeline"); pause(6); shot("rt-\(v)")
            tapID(app, "mapCard"); pause(6); shot("rt-\(v)-full")
            app.terminate()
        }
    }

    /// Previews for David: sign-in sheets sized to content, splash A/B/C, streak day opening the Day score page.
    func testPreviewsDemo() throws {
        var app = XCUIApplication()
        app.launchArguments = ["-demo", "-onboarding", "-signin.pinned", "YES"]
        app.launchEnvironment["TZ"] = Self.morningZone
        app.launch(); pause(1.5)
        tapID(app, "splashContinue"); pause(1.8); shot("pv-signin-fit")
        tapID(app, "signInOption-Apple"); pause(0.5)
        tapID(app, "signInContinue"); pause(1.8); shot("pv-apple-fit")
        app.terminate()
        for v in ["D", "E", "F", "G"] {
            app = XCUIApplication()
            app.launchArguments = ["-demo", "-onboarding", "-splash.style", v]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch(); pause(1.8); shot("pv-splash-\(v)")
            app.terminate()
        }
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-streak.dayOpens", "score"]
        app.launchEnvironment["TZ"] = Self.morningZone
        app.launch()
        tab(app, "Insights"); pause(1.5)
        app.buttons["Month"].firstMatch.tap(); pause(1.2)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Streak'")).firstMatch.tap(); pause(2)
        let hist = app.descendants(matching: .any)["streakHistory"].firstMatch
        if hist.waitForExistence(timeout: 3) { hist.swipeUp(); pause(1) }
        let d = Calendar.current.component(.day, from: Calendar.current.date(byAdding: .day, value: -3, to: .now)!)
        let cell = app.descendants(matching: .any)["historyDay-\(d)"].firstMatch
        if cell.waitForExistence(timeout: 3) { cell.tap(); pause(2); shot("pv-streak-score") }
        app.terminate()
    }

    /// Journal editor demo: camera/photo button options with the keyboard up.
    func testEditorDemo() throws {
        for v in ["B", "C"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-editor.buttons", v]
            app.launchEnvironment["TZ"] = Self.morningZone
            app.launch()
            tab(app, "Journal"); pause(2)
            tapID(app, "newEntry"); pause(2)
            let tip = app.buttons["Continue"]; if tip.waitForExistence(timeout: 2) { tip.tap(); pause(1) }
            let title = app.descendants(matching: .any)["entryTitle"].firstMatch
            if title.waitForExistence(timeout: 3) { title.tap(); pause(1); title.typeText("Morning walk") }
            let body = app.descendants(matching: .any)["entryBody"].firstMatch
            if body.waitForExistence(timeout: 3) { body.tap(); pause(1); body.typeText("Coffee at the park, then a slow loop around the lake") }
            pause(1.5); shot("e\(v)-editor-typing")
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
}
