import XCTest

/// Walks through every screen with demo data. CI records the simulator screen while these run,
/// which produces the preview videos, and saves a screenshot of each screen.
final class DemoTourTests: XCTestCase {
    static let shotDir = "/tmp/dayline-shots"

    /// A time zone where the local time is about 9:30 AM right now, so the demo day looks like the design.
    static var morningZone: String {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let hour = utc.component(.hour, from: .now)
        var offset = (9 - hour + 24) % 24
        if offset > 14 { offset -= 24 }
        // POSIX Etc zones have the sign flipped: Etc/GMT-8 is UTC+8.
        return offset == 0 ? "UTC" : "Etc/GMT\(offset > 0 ? "-" : "+")\(abs(offset))"
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
        tapID(app, "splashContinue"); pause(1.5); shot("02-sign-in-sheet")
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
        tapID(app, "permissionsContinue"); pause(1.2); shot("06d-permissions-notifications")
        tapID(app, "permissionsContinue"); pause(3); shot("07-today-after-sign-in")
    }

    /// The email sign-up path (screenshots only).
    func testOnboardingEmail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-onboarding"]
        app.launchEnvironment["TZ"] = Self.morningZone
        app.launch()
        pause(2.5)
        for _ in 0..<3 { tapID(app, "introContinue"); pause(1) }
        pause(0.5)
        tapID(app, "emailSignIn"); pause(1.5)
        let email = app.textFields["emailField"]; _ = email.waitForExistence(timeout: 5); email.tap(); email.typeText("alex@example.com"); pause(1); shot("05a-email")
        tapID(app, "setupPrimary"); pause(1.5)
        let eCode = app.textFields["emailCodeField"]; _ = eCode.waitForExistence(timeout: 5); eCode.tap(); eCode.typeText("5710"); pause(1); shot("05b-email-code")
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
        tapID(app, "takeMeBack"); pause(3.5); shot("12-take-me-back")
        app.swipeUp(); pause(1.5); shot("13-take-me-back-scrolled"); app.swipeDown(); pause(1)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 3) { back.tap() }
        pause(1.5)

        tab(app, "Insights"); pause(2.5); shot("30-insights-month")
        tapID(app, "streakCard"); pause(2); shot("33-streak")
        tapID(app, "friend-Sam"); pause(2); shot("34-friend"); goBack(app)
        tapID(app, "peopleButton"); pause(2); shot("35-people")
        app.swipeUp(); pause(1.2); shot("35b-people-scrolled"); app.swipeDown(); pause(1)
        tapID(app, "person-Sam"); pause(2); shot("36-person-sam"); goBack(app); pause(1)
        tapID(app, "askToShare"); pause(2); shot("37-ask-to-share"); goBack(app); pause(1)
        app.swipeUp(); pause(1)
        tapID(app, "addPerson"); pause(2); shot("38-share-with"); goBack(app); pause(1)
        tapID(app, "invite-Maya Cohen"); pause(2.5); shot("39-invite-sheet")
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 2) { close.tap() } else { app.swipeDown(velocity: .fast) }
        pause(1.5)
        goBack(app)
        goBack(app)
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
            tapID(app, "saveEntry"); pause(2); shot("52-journal-after-save")
        }
        // Profile > Background: pick a preset and show it behind Today.
        tab(app, "Profile"); pause(2); shot("60-profile")
        app.swipeUp(); pause(1.2); shot("60b-profile-bottom")
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
            if row.waitForExistence(timeout: 3) { row.tap(); pause(3); shot(name); app.activate(); pause(1.5) }
        }
        let appearance = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Appearance")).firstMatch
        if appearance.waitForExistence(timeout: 3) { appearance.tap(); pause(1.2); shot("60c-appearance-menu"); app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap(); pause(0.8) }
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
        tapID(app, "yourDataRow"); pause(2); shot("65-your-data"); goBack(app)
        tab(app, "Today"); pause(1.5); shot("63-today-sunset")
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

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }
}
