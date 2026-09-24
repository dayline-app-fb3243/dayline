import SwiftUI
import CoreMotion
import AVFoundation
import Photos
import AuthenticationServices

/// First launch: splash -> sign-in sheet (Apple / Google / Email) -> phone -> code -> permissions -> app.
struct OnboardingFlow: View {
    @AppStorage("onboarding.done") private var done = false
    @State private var step: Step = .splash
    enum Step { case splash, email, emailCode, phone, code, permissions }

    var body: some View {
        ZStack {
            switch step {
            case .splash: SplashView(next: { withAnimation(.smooth) { step = .phone } },
                                     email: { withAnimation(.smooth) { step = .email } })
            case .email: EmailView(next: { withAnimation(.smooth) { step = .emailCode } },
                                   back: { withAnimation(.smooth) { step = .splash } })
            case .emailCode: EmailCodeView(next: { withAnimation(.smooth) { step = .phone } },
                                           back: { withAnimation(.smooth) { step = .email } })
            case .phone: PhoneNumberView(next: { withAnimation(.smooth) { step = .code } },
                                         later: { withAnimation(.smooth) { step = .permissions } })
            case .code: PhoneCodeView(next: { withAnimation(.smooth) { step = .permissions } },
                                      back: { withAnimation(.smooth) { step = .phone } })
            case .permissions: PermissionsView { withAnimation(.smooth) { done = true } }
            }
        }
        .transition(.opacity)
    }
}

struct AppMark: View {
    var size: CGFloat = 96
    var shadow = true
    var body: some View {
        // The exact app icon (#5), so every in-app logo matches the Home Screen icon.
        Image("AppIconImage").resizable().interpolation(.high)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .frame(width: size, height: size)
        .shadow(color: .blue.opacity(shadow ? 0.3 : 0), radius: size * 0.19, y: size * 0.08)
    }
}

/// Icon #5 "Two rings": outer ring 80% full, inner ring 60%, white on blue.
struct DayRings: View {
    var size: CGFloat
    var body: some View {
        let u = size / 100
        ZStack {
            ring(r: 30 * u, w: 11 * u, frac: 0.8, color: .white)
            ring(r: 17 * u, w: 11 * u, frac: 0.6, color: .white.opacity(0.72))
        }
        .frame(width: size, height: size)
    }
    private func ring(r: CGFloat, w: CGFloat, frac: CGFloat, color: Color) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: w)
            Circle().trim(from: 0, to: frac)
                .stroke(color, style: StrokeStyle(lineWidth: w, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: r * 2, height: r * 2)
    }
}

/// The one splash: map on top, big left title, Continue opens the sign-in sheet.
struct SplashView: View {
    var next: () -> Void
    var email: () -> Void
    @State private var showSignIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(maxWidth: .infinity).frame(height: 560)
                .overlay(alignment: .top) { Image("SplashMap").resizable().scaledToFill() }
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(stops: [.init(color: Color(.systemBackground).opacity(0), location: 0), .init(color: Color(.systemBackground), location: 0.8)],
                                   startPoint: .top, endPoint: .bottom).frame(height: 220)
                }
                .ignoresSafeArea(edges: .top)
            VStack(alignment: .leading, spacing: 10) {
                Text("Your day,\nremembered.").font(.largeTitle.bold())
                Text("Dayline builds your timeline from where you go. Low-power, so it\u{2019}s easy on your battery.")
                    .font(.body).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28).padding(.top, -40)
            Spacer()
            Button { showSignIn = true } label: { Text("Continue").font(.headline).frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(.extraLarge)
                .padding(.horizontal, 24).padding(.bottom, 16)
                .accessibilityIdentifier("splashContinue")
        }
        .background(Color(.systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("splash")
        .sheet(isPresented: $showSignIn) {
            SignInSheet(next: { showSignIn = false; next() }, email: { showSignIn = false; email() })
                .presentationDetents([.height(500)])
        }
    }
}

/// Sign-in sheet in the style of Apple's own "Sign in with Apple" sheet: pick one, then the blue button.
struct SignInSheet: View {
    var next: () -> Void
    var email: () -> Void
    enum Option: String, CaseIterable { case apple = "Apple", google = "Google", email = "Email" }
    @State private var choice: Option = .apple
    @State private var showAppleDemo = false
    @State private var appleDone = false
    @ObservedObject private var auth = AuthService.shared
    @Environment(\.dismiss) private var dismiss
    private let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")
    @State private var apple = AppleSignInRunner()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sign In to Dayline").font(.title2.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44) }
                    .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Close")
            }
            HStack(spacing: 14) {
                AppMark(size: 56).shadow(radius: 0)
                Text("Choose how you want to sign in. Your timeline stays on your iPhone.").font(.subheadline)
            }
            .padding(.top, 10)
            VStack(spacing: 0) {
                ForEach(Option.allCases, id: \.self) { o in
                    Button { choice = o } label: { row(o) }.buttonStyle(.plain)
                        .accessibilityIdentifier("signInOption-\(o.rawValue)")
                    if o != .email { Divider().padding(.leading, 60) }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24, style: .continuous))
            .padding(.top, 16)
            Button(action: go) { Text("Continue with \(choice.rawValue)").font(.headline).padding(.horizontal, 10) }
                .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(.large)
                .frame(maxWidth: .infinity).padding(.top, 18)
                .accessibilityIdentifier("signInContinue")
            if let error = auth.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity).padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 20)
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showAppleDemo, onDismiss: {
            // Only move on once the Apple sheet is fully gone, so the sign-in sheet can close too.
            if appleDone { next() }
        }) {
            AppleSignInDemoSheet {
                Task { await auth.signInDemo(provider: .apple); appleDone = true; showAppleDemo = false }
            }
            .presentationDetents([.height(520)])
        }
    }

    private func row(_ o: Option) -> some View {
        HStack(spacing: 16) {
            Group {
                switch o {
                case .apple: Image(systemName: "apple.logo").font(.title3)
                case .google: GoogleG().frame(width: 20, height: 20)
                case .email: Image(systemName: "envelope.fill").font(.body)
                }
            }
            .foregroundStyle(.primary).frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(o.rawValue).foregroundStyle(.primary)
                Text(o == .apple ? "Fastest, uses Face ID" : o == .google ? "Your Google account" : "We\u{2019}ll send you a code")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: choice == o ? "checkmark.circle.fill" : "circle")
                .font(.title3).foregroundStyle(choice == o ? Theme.accent : Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16).frame(minHeight: 62).contentShape(.rect)
    }

    /// The simulator has no Apple Account, so sign-in runs as a demo there.
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private func go() {
        switch choice {
        case .apple:
            if isDemo || Self.isSimulator { showAppleDemo = true; return }
            apple.start { result in Task { await auth.handleApple(result); if auth.isSignedIn { next() } } }
        case .google:
            Task { if isDemo || Self.isSimulator { await auth.signInDemo(provider: .google); next() } else { await auth.signInWithGoogle(); if auth.isSignedIn { next() } } }
        case .email: email()
        }
    }
}

/// Runs the real Sign in with Apple request (shows Apple's own sheet).
@MainActor
final class AppleSignInRunner: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var done: ((Result<ASAuthorization, Error>) -> Void)?
    func start(_ done: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.done = done
        let request = ASAuthorizationAppleIDProvider().createRequest()
        AuthService.shared.configure(request)
        let c = ASAuthorizationController(authorizationRequests: [request])
        c.delegate = self; c.presentationContextProvider = self
        c.performRequests()
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) { done?(.success(authorization)) }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) { done?(.failure(error)) }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }
}

/// Demo stand-in for Apple's own Sign in with Apple sheet (the real one needs a paid developer account).
/// Laid out like the real iOS 26 sheet.
struct AppleSignInDemoSheet: View {
    var onContinue: () -> Void
    @State private var hideEmail = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sign in with Apple").font(.title2.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
            }
            HStack(spacing: 14) {
                AppMark(size: 56).shadow(radius: 0)
                Text("Create an account for Dayline using your Apple Account (alex@icloud.com).").font(.subheadline)
            }
            .padding(.top, 10)
            HStack(spacing: 16) {
                Image(systemName: "person.fill").frame(width: 28)
                VStack(alignment: .leading, spacing: 1) { Text("Name"); Text("Alex Morgan").font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
                Image(systemName: "xmark.circle.fill").foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16).frame(minHeight: 60)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24, style: .continuous))
            .padding(.top, 16)
            VStack(spacing: 0) {
                choice("Share My Email", "alex@icloud.com", selected: !hideEmail) { hideEmail = false }
                Divider().padding(.leading, 60)
                choice("Hide My Email", "Forward To: alex@icloud.com", selected: hideEmail) { hideEmail = true }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24, style: .continuous))
            .padding(.top, 10)
            Button(action: onContinue) { Text("Continue").font(.headline).padding(.horizontal, 30) }
                .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(.large)
                .frame(maxWidth: .infinity).padding(.top, 18)
                .accessibilityIdentifier("appleDemoContinue")
            Text("Use a different Apple Account").font(.subheadline).foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity).padding(.top, 12)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 20)
        .background(Color(.systemGroupedBackground))
    }

    private func choice(_ title: String, _ detail: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "envelope.fill").frame(width: 28).foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(selected ? Theme.accent : Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16).frame(minHeight: 60).contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// The four-color Google "G", drawn so no image asset is needed.
struct GoogleG: View {
    var body: some View {
        Canvas { ctx, size in
            let w = min(size.width, size.height), c = CGPoint(x: size.width / 2, y: size.height / 2), r = w * 0.38
            let line = w * 0.2
            func arc(_ from: Double, _ to: Double, _ color: Color) {
                var p = Path()
                p.addArc(center: c, radius: r, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                ctx.stroke(p, with: .color(color), lineWidth: line)
            }
            arc(-40, 45, Color(red: 0.26, green: 0.52, blue: 0.96))   // blue
            arc(45, 135, Color(red: 0.2, green: 0.66, blue: 0.33))    // green
            arc(135, 200, Color(red: 0.98, green: 0.74, blue: 0.02))  // yellow
            arc(200, 320, Color(red: 0.92, green: 0.26, blue: 0.21))  // red
            var bar = Path()
            bar.addRect(CGRect(x: c.x, y: c.y - line / 2, width: r + line / 2, height: line))
            ctx.fill(bar, with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)))
        }
    }
}

/// One page per permission, Apple's pattern: left title, blue symbols, a note, Continue.
/// Continue shows iPhone's own system prompt (never a drawn one), then moves on.
struct PermissionsView: View {
    var next: () -> Void
    private let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")
    @State private var index = 0

    private struct Page { var kind: String; var title: String; var rows: [(String, String)]; var note: String }
    private let pages: [Page] = [
        Page(kind: "location", title: "Turning on Location lets Dayline:",
             rows: [("list.bullet", "Build your timeline for you"), ("map", "Show where you were on a map"), ("clock.arrow.circlepath", "Find a place again with Siri")],
             note: "It\u{2019}s low-power, so it\u{2019}s easy on your battery. You can change this later in Settings."),
        Page(kind: "photos", title: "Turning on Photos lets Dayline:",
             rows: [("photo.on.rectangle", "Put your photos on the places you took them"), ("calendar", "Show them on your day")],
             note: "Your photos stay on your iPhone. You can change this later in Settings."),
        Page(kind: "mic", title: "Turning on the Microphone lets Dayline:",
             rows: [("mic", "Record voice notes for your journal"), ("text.bubble", "Turn them into text on your iPhone")],
             note: "Dayline only listens while you record. You can change this later in Settings."),
        Page(kind: "motion", title: "Turning on Motion & Fitness lets Dayline:",
             rows: [("moon", "Tell when you fell asleep, so late nights count toward the right day"), ("sun.max", "Know when you woke up"), ("figure.walk", "Count steps and walks in your day")],
             note: "Motion stays on your iPhone. You can change this later in Settings."),
        Page(kind: "health", title: "Turning on Apple Health lets Dayline:",
             rows: [("figure.run", "Add your runs and walks to your timeline"), ("dumbbell", "Mark gym workouts done on your schedule"), ("heart", "Only read workouts. Dayline never writes to Health")],
             note: "Health data stays on your iPhone. You can change this later in Settings."),
        Page(kind: "reminders", title: "Turning on Reminders lets Dayline:",
             rows: [("checklist", "Count reminders due today in your day score"), ("checkmark.circle", "Give you points when you finish them"), ("eye", "Only read them. Dayline never changes your reminders")],
             note: "Reminders stay on your iPhone. You can change this later in Settings."),
        Page(kind: "notifications", title: "Turning on Notifications lets Dayline:",
             rows: [("person.badge.plus", "Tell you when someone asks to follow you"), ("star", "Tell you when you hit 80")],
             note: "That\u{2019}s it, only those 2. You can change this later in Settings."),
    ]

    var body: some View {
        let page = pages[index]
        VStack(alignment: .leading, spacing: 0) {
            Text(page.title).font(.title.bold()).padding(.top, 60).padding(.bottom, 30)
            ForEach(page.rows, id: \.1) { r in
                HStack(spacing: 16) {
                    Image(systemName: r.0).font(.title2).foregroundStyle(Theme.accent).frame(width: 36)
                    Text(r.1).font(.body)
                }
                .padding(.bottom, 24)
            }
            Text(page.note).font(.body).padding(.top, 4)
            Spacer()
            Button { Task { await request(page.kind); advance() } } label: {
                Text("Continue").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(.extraLarge)
            .accessibilityIdentifier("permissionsContinue")
        }
        .padding(.horizontal, 28).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .id(index)
        .transition(.push(from: .trailing))
    }

    private func advance() {
        if index < pages.count - 1 { withAnimation(.smooth) { index += 1 } } else { next() }
    }

    @MainActor private func request(_ kind: String) async {
        guard !isDemo else { return }
        switch kind {
        case "location":
            LocationService.shared.requestPermission()
            // Wait for the answer to iPhone's prompt (up to a minute).
            for _ in 0..<120 where LocationService.shared.authorization == .notDetermined {
                try? await Task.sleep(for: .milliseconds(500))
            }
        case "photos": _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        case "mic": _ = await AVAudioApplication.requestRecordPermission()
        case "health": await HealthService.shared.requestAccess()
        case "reminders": _ = await RemindersService.shared.requestAccess()
        case "motion":
            DayBoundary.shared.requestMotion()
            for _ in 0..<120 where DayBoundary.motionAvailable && CMMotionActivityManager.authorizationStatus() == .notDetermined {
                try? await Task.sleep(for: .milliseconds(500))
            }
        default: await Notifications.requestPermission()
        }
    }
}

// MARK: - Phone number (iPhone Setup style, option A)

/// Shared layout for the setup-style steps: glass back button, blue line icon,
/// left-aligned title + gray subtitle, and the two big buttons at the bottom.
struct SetupStep<Content: View>: View {
    var symbol: String
    var title: String
    var subtitle: String
    var primary: String
    var primaryEnabled: Bool
    var secondary: String?
    /// true = small blue text link under Continue instead of a second big button.
    var secondaryIsLink: Bool = false
    var back: (() -> Void)?
    var onPrimary: () -> Void
    var onSecondary: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let back {
                    Button(action: back) { Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 44, height: 44) }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                }
                Spacer()
            }
            .frame(height: 44)
            Image(systemName: symbol).font(.system(size: 60, weight: .light)).foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity).padding(.top, 20)
            Text(title).font(.title2.bold()).padding(.top, 26)
            Text(subtitle).font(.title3).foregroundStyle(.secondary).padding(.top, 4)
            content.padding(.top, 24)
            Spacer()
            VStack(spacing: 10) {
                // Apple's standard filled button: large control size, system semibold text.
                Button(action: onPrimary) { Text(primary).font(.headline).frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).buttonBorderShape(.capsule)
                    .disabled(!primaryEnabled).accessibilityIdentifier("setupPrimary")
                if let secondary {
                    if secondaryIsLink {
                        Button(secondary, action: onSecondary).font(.subheadline).foregroundStyle(Theme.accent)
                            .accessibilityIdentifier("setupSecondary")
                    } else {
                        Button(action: onSecondary) { Text(secondary).font(.headline).frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule).accessibilityIdentifier("setupSecondary")
                    }
                }
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 32).padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
    }
}

struct PhoneNumberView: View {
    var next: () -> Void
    var later: () -> Void
    @AppStorage("auth.phone") private var savedPhone = ""
    @AppStorage("auth.countryCode") private var countryCode = "+1"
    @AppStorage("auth.region") private var region = "US"
    static let regions = [("US", "+1"), ("CA", "+1"), ("GB", "+44"), ("IL", "+972"), ("FR", "+33"), ("DE", "+49"), ("MX", "+52")]
    @State private var digits = ""
    @FocusState private var focused: Bool

    private var formatted: String {
        let d = Array(digits.prefix(10))
        guard countryCode == "+1" else { return String(d) }
        var out = ""
        for (i, c) in d.enumerated() {
            if i == 0 { out += "(" }
            if i == 3 { out += ") " }
            if i == 6 { out += "-" }
            out.append(c)
        }
        return out
    }

    var body: some View {
        SetupStep(symbol: "iphone.gen3.badge.checkmark", title: "Phone Number",
                  subtitle: "Enter your number so friends can find you and share their streaks with you.",
                  primary: "Continue", primaryEnabled: digits.count >= 10, secondary: "Set Up Later",
                  back: nil, onPrimary: { savedPhone = countryCode + digits; next() }, onSecondary: later) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(Self.regions, id: \.0) { r in
                            Button("\(r.0) \(r.1)") { region = r.0; countryCode = r.1 }
                        }
                    } label: {
                        HStack(spacing: 6) { Text("\(region) \(countryCode)"); Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                            .foregroundStyle(.primary).padding(.horizontal, 16).frame(height: 52)
                            .background(Color(.tertiarySystemFill), in: .capsule)
                    }
                    TextField("Phone Number", text: Binding(get: { formatted }, set: { digits = String($0.filter(\.isNumber).prefix(15)) }))
                        .keyboardType(.numberPad).textContentType(.telephoneNumber).focused($focused)
                        .padding(.horizontal, 18).frame(height: 52)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                        .accessibilityIdentifier("phoneField")
                }
                Label("Friends who have this number in their contacts can find you. It's never shown to anyone.", systemImage: "info.circle.fill")
                    .font(.footnote).foregroundStyle(.secondary)
                    .labelStyle(InfoLabelStyle())
            }
        }
        .onAppear { focused = true }
    }
}

private struct InfoLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.foregroundStyle(Theme.accent)
            configuration.title
        }
    }
}

struct PhoneCodeView: View {
    var next: () -> Void
    var back: () -> Void
    @AppStorage("auth.phone") private var savedPhone = ""
    @AppStorage("auth.phoneVerified") private var verified = false
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        SetupStep(symbol: "ellipsis.message", title: "Enter Code",
                  subtitle: "Enter the 6-digit code sent to \(savedPhone).",
                  primary: "Continue", primaryEnabled: code.count == 6, secondary: "Change Number", secondaryIsLink: true,
                  back: back, onPrimary: {
                      // No text-message service is connected yet, so any 6 digits are accepted in this build.
                      verified = true; next()
                  }, onSecondary: back) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    TextField("", text: Binding(get: { code }, set: { code = String($0.filter(\.isNumber).prefix(6)) }))
                        .keyboardType(.numberPad).textContentType(.oneTimeCode).focused($focused)
                        .foregroundStyle(.clear).tint(.clear)
                        .accessibilityIdentifier("codeField")
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { i in
                            let chars = Array(code)
                            Text(i < chars.count ? String(chars[i]) : "")
                                .font(.title.weight(.medium))
                                .frame(maxWidth: .infinity).frame(height: 58)
                                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent, lineWidth: i == code.count && focused ? 2 : 0))
                        }
                    }
                    .allowsHitTesting(false)
                }
                .onTapGesture { focused = true }
                Button("Didn't get a code?") {}.font(.subheadline)
            }
        }
        .onAppear { focused = true }
    }
}

struct EmailView: View {
    var next: () -> Void
    var back: () -> Void
    @AppStorage("auth.email") private var savedEmail = ""
    @State private var email = ""
    @FocusState private var focused: Bool
    private var valid: Bool { email.contains("@") && email.split(separator: "@").last?.contains(".") == true }

    var body: some View {
        SetupStep(symbol: "envelope", title: "Email Address",
                  subtitle: "Enter your email to back up your timeline and sign in on other devices.",
                  primary: "Continue", primaryEnabled: valid, secondary: nil,
                  back: back, onPrimary: { savedEmail = email; next() }, onSecondary: back) {
            TextField("name@example.com", text: $email)
                .keyboardType(.emailAddress).textContentType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused)
                .padding(.horizontal, 18).frame(height: 52)
                .background(Color(.tertiarySystemFill), in: .capsule)
                .accessibilityIdentifier("emailField")
        }
        .onAppear { focused = true }
    }
}

struct EmailCodeView: View {
    var next: () -> Void
    var back: () -> Void
    @AppStorage("auth.email") private var savedEmail = ""
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        SetupStep(symbol: "envelope.badge", title: "Check Your Email",
                  subtitle: "Enter the 6-digit code sent to \(savedEmail).",
                  primary: "Continue", primaryEnabled: code.count == 6, secondary: nil,
                  back: back, onPrimary: {
                      // No email service is connected yet, so any 6 digits are accepted in this build.
                      Task { await AuthService.shared.signInDemo(provider: .email); next() }
                  }, onSecondary: back) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    TextField("", text: Binding(get: { code }, set: { code = String($0.filter(\.isNumber).prefix(6)) }))
                        .keyboardType(.numberPad).textContentType(.oneTimeCode).focused($focused)
                        .foregroundStyle(.clear).tint(.clear)
                        .accessibilityIdentifier("emailCodeField")
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { i in
                            let chars = Array(code)
                            Text(i < chars.count ? String(chars[i]) : "")
                                .font(.title.weight(.medium))
                                .frame(maxWidth: .infinity).frame(height: 58)
                                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent, lineWidth: i == code.count && focused ? 2 : 0))
                        }
                    }
                    .allowsHitTesting(false)
                }
                .onTapGesture { focused = true }
                Button("Resend Code") {}.font(.subheadline)
            }
        }
        .onAppear { focused = true }
    }
}
