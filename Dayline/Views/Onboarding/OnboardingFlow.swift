import SwiftUI
import AuthenticationServices

/// First launch: splash -> 3 intro pages -> sign in -> permissions -> app.
struct OnboardingFlow: View {
    @AppStorage("onboarding.done") private var done = false
    @State private var step: Step = .splash
    enum Step { case splash, intro, signIn, email, emailCode, phone, code, permissions }

    var body: some View {
        ZStack {
            switch step {
            case .splash: SplashView { withAnimation(.smooth) { step = .intro } }
            case .intro: IntroPages { withAnimation(.smooth) { step = .signIn } }
            case .signIn: SignInView(next: { withAnimation(.smooth) { step = .phone } },
                                     email: { withAnimation(.smooth) { step = .email } })
            case .email: EmailView(next: { withAnimation(.smooth) { step = .emailCode } },
                                   back: { withAnimation(.smooth) { step = .signIn } })
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
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.55, blue: 1), Color(red: 0.45, green: 0.35, blue: 0.95)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .blue.opacity(0.3), radius: 18, y: 8)
    }
}

struct SplashView: View {
    var next: () -> Void
    @State private var appear = false
    var body: some View {
        VStack(spacing: 18) {
            AppMark().scaleEffect(appear ? 1 : 0.8).opacity(appear ? 1 : 0)
            Text("Dayline").font(.largeTitle.bold()).opacity(appear ? 1 : 0)
            Text("Your day, written for you.").font(.headline).foregroundStyle(.secondary).opacity(appear ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .accessibilityIdentifier("splash")
        .task {
            withAnimation(.spring(duration: 0.8)) { appear = true }
            try? await Task.sleep(for: .seconds(1.8))
            next()
        }
    }
}

struct IntroPages: View {
    var next: () -> Void
    @State private var page = 0
    private let pages: [(String, String, String, Color)] = [
        ("calendar.day.timeline.left", "Your day builds itself",
         "Dayline learns your routine from where you go and fills in your schedule. No typing.", Theme.accent),
        ("car.fill", "\"Take me back there\"",
         "Ask Siri for the place you ate four days ago. See your photos from it and get directions.", Theme.accent),
        ("battery.100percent.bolt", "Private and light on battery",
         "Tracks your route only while you are moving and rests when you stop. Everything stays on your iPhone.", Theme.accent)
    ]
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    let p = pages[i]
                    VStack(spacing: 22) {
                        Spacer()
                        Image(systemName: p.0).font(.system(size: 64, weight: .semibold)).foregroundStyle(p.3)
                            .frame(width: 150, height: 150)
                            .background(Color(.secondarySystemGroupedBackground), in: .circle)
                        Text(p.1).font(.title.bold()).multilineTextAlignment(.center)
                        Text(p.2).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                        Spacer(); Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button { page < pages.count - 1 ? withAnimation { page += 1 } : next() } label: {
                Text(page < pages.count - 1 ? "Continue" : "Get Started").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .padding(.horizontal, 24).padding(.bottom, 16)
            .accessibilityIdentifier("introContinue")
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct SignInView: View {
    var next: () -> Void
    var email: () -> Void
    @ObservedObject private var auth = AuthService.shared
    @Environment(\.colorScheme) private var scheme
    private let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")
    @State private var showAppleDemo = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            AppMark(size: 84)
            Text("Welcome to Dayline").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Sign in to back up your timeline and keep it across devices.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()

            SignInWithAppleButton(.signIn) { auth.configure($0) } onCompletion: { result in
                Task { await auth.handleApple(result); if auth.isSignedIn { next() } }
            }
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 54)
            .clipShape(.capsule)
            .allowsHitTesting(!isDemo)
            .overlay {
                // Demo builds aren't signed with an Apple developer account, so show a stand-in sheet.
                if isDemo { Color.clear.contentShape(.capsule).onTapGesture { showAppleDemo = true } }
            }
            .accessibilityIdentifier("appleSignIn")

            Button {
                Task {
                    if isDemo { await auth.signInDemo(provider: .google); next() } else { await auth.signInWithGoogle(); if auth.isSignedIn { next() } }
                }
            } label: {
                HStack(spacing: 10) {
                    GoogleG().frame(width: 20, height: 20)
                    Text("Sign in with Google").font(.system(size: 19, weight: .medium))
                }
                .frame(maxWidth: .infinity).frame(height: 54)
                .foregroundStyle(.primary)
                .background(Color(.secondarySystemGroupedBackground), in: .capsule)
                .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
            }
            .accessibilityIdentifier("googleSignIn")

            Button(action: email) {
                Label("Continue with Email", systemImage: "envelope.fill")
                    .font(.system(size: 19, weight: .medium))
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .foregroundStyle(.primary)
                    .background(Color(.secondarySystemGroupedBackground), in: .capsule)
                    .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
            }
            .accessibilityIdentifier("emailSignIn")

            Text("By continuing, you agree to Dayline's Terms and Privacy Policy.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 4)

            if let error = auth.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showAppleDemo) {
            AppleSignInDemoSheet {
                showAppleDemo = false
                Task { await auth.signInDemo(provider: .apple); next() }
            }
            .presentationDetents([.height(560)])
        }
    }
}

/// Demo stand-in for the system Sign in with Apple sheet (the real one needs a paid developer account).
struct AppleSignInDemoSheet: View {
    var onContinue: () -> Void
    @State private var hideEmail = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                Spacer()
            }
            Image(systemName: "apple.logo").font(.system(size: 34)).padding(.top, 2)
            Text("Sign in with Apple").font(.title2.bold()).padding(.top, 8)
            AppMark(size: 56).padding(.top, 16)
            Text("Create an account for Dayline using your Apple Account \u{201C}alex@icloud.com\u{201D}.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 12).padding(.horizontal, 20)
            VStack(spacing: 0) {
                HStack { Image(systemName: "person.circle.fill").foregroundStyle(.secondary); Text("Alex Morgan"); Spacer() }
                    .padding(.horizontal, 16).frame(height: 48)
                Divider().padding(.leading, 44)
                choice("Share My Email", "alex@icloud.com", selected: !hideEmail) { hideEmail = false }
                Divider().padding(.leading, 44)
                choice("Hide My Email", "Forward to alex@icloud.com", selected: hideEmail) { hideEmail = true }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22, style: .continuous))
            .padding(.top, 18)
            Spacer(minLength: 12)
            Button(action: onContinue) { Text("Continue").font(.headline).frame(maxWidth: .infinity).frame(height: 40) }
                .buttonStyle(.glassProminent).controlSize(.large)
                .accessibilityIdentifier("appleDemoContinue")
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
        .background(Color(.systemGroupedBackground))
    }

    private func choice(_ title: String, _ detail: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.blue : Color(.tertiaryLabel)).font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16).frame(height: 56).contentShape(.rect)
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

struct PermissionsView: View {
    var next: () -> Void
    private let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A few permissions").font(.largeTitle.bold()).padding(.top, 40)
            Text("Dayline works best with these. You can change them any time in Settings.")
                .foregroundStyle(.secondary)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    row("location.fill", .blue, "Location", "Builds your timeline and learns your routine")
                    Divider().padding(.leading, 62)
                    row("photo.fill", Theme.accent, "Photos", "Puts your photos where you took them")
                    Divider().padding(.leading, 62)
                    row("mic.fill", Theme.accent, "Microphone", "Voice notes, turned into text on your iPhone")
                    Divider().padding(.leading, 62)
                    row("bell.fill", Theme.accent, "Notifications", "When someone asks to follow you, or you hit 80")
                }
            }
            Spacer()
            Button {
                if !isDemo {
                    LocationService.shared.requestPermission()
                    Task { await Notifications.requestPermission() }
                }
                next()
            } label: { Text("Allow and Continue").font(.headline).frame(maxWidth: .infinity) }
            .buttonStyle(.glassProminent).controlSize(.extraLarge)
            .accessibilityIdentifier("permissionsContinue")
        }
        .padding(.horizontal, 22).padding(.bottom, 16)
        .background(Color(.systemGroupedBackground))
    }

    private func row(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).foregroundStyle(.white).frame(width: 34, height: 34)
                .background(color.gradient, in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
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
    var secondary: String
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
            Image(systemName: symbol).font(.system(size: 60, weight: .light)).foregroundStyle(.blue)
                .frame(maxWidth: .infinity).padding(.top, 20)
            Text(title).font(.title2.bold()).padding(.top, 26)
            Text(subtitle).font(.title3).foregroundStyle(.secondary).padding(.top, 4)
            content.padding(.top, 24)
            Spacer()
            VStack(spacing: 10) {
                Button(action: onPrimary) { Text(primary).font(.headline).frame(maxWidth: .infinity).frame(height: 40) }
                    .buttonStyle(.glassProminent).disabled(!primaryEnabled).accessibilityIdentifier("setupPrimary")
                Button(action: onSecondary) { Text(secondary).font(.headline).frame(maxWidth: .infinity).frame(height: 40) }
                    .buttonStyle(.glass).foregroundStyle(.primary).accessibilityIdentifier("setupSecondary")
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
            configuration.icon.foregroundStyle(.blue)
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
                  primary: "Continue", primaryEnabled: code.count == 6, secondary: "Change Number",
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
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.blue, lineWidth: i == code.count && focused ? 2 : 0))
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
                  primary: "Continue", primaryEnabled: valid, secondary: "Use Sign in with Apple",
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
                  primary: "Continue", primaryEnabled: code.count == 6, secondary: "Change Email",
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
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.blue, lineWidth: i == code.count && focused ? 2 : 0))
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
