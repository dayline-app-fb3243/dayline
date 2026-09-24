import SwiftUI
import MapKit
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
    /// "mark.rings": rings-only logo color light to deep (set "" for the old square icon): just the two rings, no square.
    /// blue = app blue, ink = black/white, sky = light-to-deep blue, duo = blue + teal.
    @AppStorage("mark.rings") private var rings = "sky"
    var body: some View {
        if rings.isEmpty { iconBody } else { RingMark(size: size, palette: rings) }
    }
    private var iconBody: some View {
        // The exact app icon (#5), so every in-app logo matches the Home Screen icon.
        Image("AppIconImage").resizable().interpolation(.high)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .frame(width: size, height: size)
        .shadow(color: .blue.opacity(shadow ? 0.3 : 0), radius: size * 0.19, y: size * 0.08)
    }
}

/// The app's two rings on their own (no icon square), for in-app logos.
struct RingMark: View {
    var size: CGFloat
    var palette: String
    var body: some View {
        let u = size / 100
        let (outer, inner): (AnyShapeStyle, AnyShapeStyle) = {
            switch palette {
            case "ink": return (AnyShapeStyle(Color.primary), AnyShapeStyle(Color.primary.opacity(0.55)))
            case "sky": return (AnyShapeStyle(LinearGradient(colors: [Color(red: 0.30, green: 0.65, blue: 1), Color(red: 0.07, green: 0.38, blue: 0.92)], startPoint: .top, endPoint: .bottom)),
                                AnyShapeStyle(Color(red: 0.45, green: 0.75, blue: 1)))
            case "duo": return (AnyShapeStyle(Theme.accent), AnyShapeStyle(Color(red: 0.19, green: 0.78, blue: 0.75)))
            default: return (AnyShapeStyle(Theme.accent), AnyShapeStyle(Theme.accent.opacity(0.6)))
            }
        }()
        ZStack {
            ring(r: 38 * u, w: 14 * u, frac: 0.8, style: outer)
            ring(r: 21 * u, w: 14 * u, frac: 0.6, style: inner)
        }
        .frame(width: size, height: size)
    }
    private func ring(r: CGFloat, w: CGFloat, frac: CGFloat, style: AnyShapeStyle) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: w)
            Circle().trim(from: 0, to: frac)
                .stroke(style, style: StrokeStyle(lineWidth: w, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: r * 2, height: r * 2)
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

    /// Preview flag "splash.style" (awaiting David's pick): "map" = faded map (now), A = clean white with the icon,
    /// B = full color map with a glass card, C = soft blue gradient with a big icon.
    @AppStorage("splash.style") private var style = "map"

    var body: some View {
        Group {
            switch style {
            case "A": splashA
            case "B": splashB
            case "C": splashC
            case "D": splashD
            case "E": splashE
            case "F": splashF
            case "G": splashG
            default: splashMap
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("splash")
        .sheet(isPresented: $showSignIn) {
            SignInSheet(next: { showSignIn = false; next() }, email: { showSignIn = false; email() })
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your day,\nremembered.").font(.largeTitle.bold())
            Text("Dayline builds your timeline from where you go. Low-power, so it\u{2019}s easy on your battery.")
                .font(.body).foregroundStyle(.secondary)
        }
    }
    private var continueButton: some View {
        Button { showSignIn = true } label: { Text("Continue").font(.headline).frame(maxWidth: .infinity) }
            .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(.extraLarge)
            .accessibilityIdentifier("splashContinue")
    }
    private var bigIcon: some View {
        Image("AppIconImage").resizable().interpolation(.high).frame(width: 120, height: 120)
            .clipShape(.rect(cornerRadius: 27, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
    }

    // A: clean white, icon on top, title under it.
    private var splashA: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            bigIcon.padding(.bottom, 28)
            title
            Spacer()
            continueButton.padding(.bottom, 16)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // B: full color map, no fade, text on a glass card.
    private var splashB: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 18) {
                title
                continueButton
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 34, style: .continuous))
            .padding(.horizontal, 14).padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Image("SplashMap").resizable().scaledToFill().ignoresSafeArea()
        }
        .clipped()
    }

    // C: soft blue gradient, big icon centered.
    private var splashC: some View {
        VStack(spacing: 0) {
            Spacer()
            bigIcon.padding(.bottom, 30)
            VStack(spacing: 10) {
                Text("Your day, remembered.").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("Dayline builds your timeline from where you go. Low-power, so it\u{2019}s easy on your battery.")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
            continueButton.padding(.bottom, 16)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.86, green: 0.92, blue: 1.0), Color(.systemBackground)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    // --- Map-based options (Sep 24, David wants ideas close to the faded map) ---
    private func fadedMap(height: CGFloat, fade: CGFloat) -> some View {
        Color.clear.frame(maxWidth: .infinity).frame(height: height)
            .overlay(alignment: .top) { Image("SplashMap").resizable().scaledToFill() }
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(stops: [.init(color: Color(.systemBackground).opacity(0), location: 0), .init(color: Color(.systemBackground), location: 0.85)],
                               startPoint: .top, endPoint: .bottom).frame(height: fade)
            }
    }
    private func bottomBlock(top: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title.padding(.horizontal, 28).padding(.top, top)
            Spacer()
            continueButton.padding(.horizontal, 24).padding(.bottom, 16)
        }
    }
    // D: taller map, longer soft fade, text sits lower.
    private var splashD: some View {
        VStack(alignment: .leading, spacing: 0) {
            fadedMap(height: 650, fade: 320).ignoresSafeArea(edges: .top)
            bottomBlock(top: -90)
        }
        .background(Color(.systemBackground))
    }
    // E: faded map with the day's stops as small glass time chips.
    private var splashE: some View {
        VStack(alignment: .leading, spacing: 0) {
            fadedMap(height: 560, fade: 220)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        chip("8:10", "Home", "house.fill")
                        chip("9:02", "Office", "briefcase.fill").padding(.leading, 40)
                        chip("12:30", "Noodle Bar", "fork.knife").padding(.leading, 90)
                    }
                    .padding(.top, 150).padding(.leading, 24)
                }
                .ignoresSafeArea(edges: .top)
            bottomBlock(top: -40)
        }
        .background(Color(.systemBackground))
    }
    private func chip(_ time: String, _ place: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
            Text(time).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(place).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
    }
    // F: the map as a rounded card at the top, title under it.
    private var splashF: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("SplashMap").resizable().scaledToFill()
                .frame(maxWidth: .infinity).frame(height: 440)
                .clipShape(.rect(cornerRadius: 36, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
                .padding(.horizontal, 16).padding(.top, 8)
            bottomBlock(top: 32)
        }
        .background(Color(.systemBackground))
    }
    // G: the faded map (now) with the app icon above the title.
    private var splashG: some View {
        VStack(alignment: .leading, spacing: 0) {
            fadedMap(height: 520, fade: 220).ignoresSafeArea(edges: .top)
            VStack(alignment: .leading, spacing: 0) {
                Image("AppIconImage").resizable().interpolation(.high).frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 15, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                    .padding(.bottom, 18)
                title
            }
            .padding(.horizontal, 28).padding(.top, -70)
            Spacer()
            continueButton.padding(.horizontal, 24).padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
    }

    /// Preview flag "splash.map" (awaiting David's pick): A/B/C = real Apple Maps with a street-following route.
    @AppStorage("splash.map") private var liveMap = ""

    private var splashMap: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(maxWidth: .infinity).frame(height: 560)
                .overlay(alignment: .top) {
                    if liveMap.isEmpty { Image("SplashMap").resizable().scaledToFill() }
                    else { SplashLiveMap(style: liveMap).frame(height: 560).allowsHitTesting(false) }
                }
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
    }
}

/// Sign-in sheet in the style of Apple's own "Sign in with Apple" sheet: pick one, then the blue button.
struct SignInSheet: View {
    @AppStorage("signin.small") private var smallButton = true
    @AppStorage("signin.pinned") private var pinned = true
    @State private var fitHeight: CGFloat = 0
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
            if let error = auth.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity).padding(.top, 8)
            }
            // Preview flag "signin.pinned" (awaiting David's OK): full-width button pinned to the bottom.
            if pinned && smallButton {
                // "signin.small" (on by default, approved in the 9/24 sign-in set): fitted sheet, small centered "Continue" pill.
                Button(action: go) { Text("Continue").font(.headline).padding(.horizontal, 30) }
                    .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(.large)
                    .frame(maxWidth: .infinity).padding(.top, 18)
                    .accessibilityIdentifier("signInContinue")
            } else if pinned {
                Button(action: go) { Text("Continue with \(choice.rawValue)").font(.headline).frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(.extraLarge)
                    .accessibilityIdentifier("signInContinue")
                    .padding(.top, 20)
            } else {
                Button(action: go) { Text("Continue with \(choice.rawValue)").font(.headline).padding(.horizontal, 10) }
                    .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(.large)
                    .frame(maxWidth: .infinity).padding(.top, 18)
                    .accessibilityIdentifier("signInContinue")
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, pinned ? 8 : 0)
        .fixedSize(horizontal: false, vertical: pinned)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fitHeight = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
        // Preview "signin.pinned": the sheet is exactly as tall as its content, like Apple's own sheets.
        .presentationDetents(pinned && fitHeight > 0 ? [.height(fitHeight + 12)] : [.height(500)])
        .sheet(isPresented: $showAppleDemo, onDismiss: {
            // Only move on once the Apple sheet is fully gone, so the sign-in sheet can close too.
            if appleDone { next() }
        }) {
            AppleSignInDemoSheet {
                Task { await auth.signInDemo(provider: .apple); appleDone = true; showAppleDemo = false }
            }
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
    @AppStorage("signin.small") private var smallButton = true
    @AppStorage("signin.pinned") private var pinned = true
    @State private var fitHeight: CGFloat = 0
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
            Button(action: onContinue) {
                if pinned && !smallButton { Text("Continue").font(.headline).frame(maxWidth: .infinity) } else { Text("Continue").font(.headline).padding(.horizontal, 30) }
            }
                .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(pinned && !smallButton ? .extraLarge : .large)
                .frame(maxWidth: .infinity).padding(.top, pinned && !smallButton ? 20 : 18)
                .accessibilityIdentifier("appleDemoContinue")
            Text("Use a different Apple Account").font(.subheadline).foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity).padding(.top, 12)
            if !pinned { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, pinned ? 8 : 0)
        .fixedSize(horizontal: false, vertical: pinned)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fitHeight = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
        .presentationDetents(pinned && fitHeight > 0 ? [.height(fitHeight + 12)] : [.height(520)])
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
             rows: [("list.bullet", "Build your timeline for you"), ("map", "Show where you were on a map"), ("siri", "Find a place again with Siri")],
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
                    Group {
                        // Every Siri mention uses the new Siri mark (David, Sep 24).
                        if r.0 == "siri" { SiriMark().frame(width: 28, height: 28) }
                        else { Image(systemName: r.0).font(.title2).foregroundStyle(Theme.accent) }
                    }
                    .frame(width: 36)
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
    var onSecondary: () -> Void = {}
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
            Image(systemName: symbol).font(.scaled(size: 60, weight: .light)).foregroundStyle(Theme.accent)
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
                  primary: "Continue", primaryEnabled: code.count == 6,
                  back: back, onPrimary: {
                      // No text-message service is connected yet, so any 6 digits are accepted in this build.
                      verified = true; next()
                  }) {
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
                Button("Didn't get a code?") {}.font(.subheadline).foregroundStyle(Theme.accent)
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
                Button("Resend Code") {}.font(.subheadline).foregroundStyle(Theme.accent)
            }
        }
        .onAppear { focused = true }
    }
}


/// Real Apple Maps behind the splash, with a walking route that follows the streets (MapKit directions),
/// like a precise GPS track, plus the day's stops. A = standard, B = muted with time labels, C = 3D.
struct SplashLiveMap: View {
    var style: String
    @State private var route: [CLLocationCoordinate2D] = []
    private struct Stop: Identifiable { let id = UUID(); let name: String; let time: String; let symbol: String; let c: CLLocationCoordinate2D }
    private var stops: [Stop] {
        switch style {
        case "P": gymStops
        case "Q": workStops
        case "R": cafeStops
        case "J", "K", "L", "M", "N": parkStops
        default: cityStops
        }
    }
    /// M/N: L's camera with one big pin on Bryant Park as the focal point (like the big pin on Apple's Maps splash).
    /// P/Q/R: M's look in other scenes: gym (Chelsea Piers), office (Rockefeller Center), coffee (Washington Square).
    private var heroSize: CGFloat? { ["M", "P", "Q", "R"].contains(style) ? 104 : style == "N" ? 132 : nil }
    private var heroName: String {
        switch style { case "P": "Gym"; case "Q": "Office"; case "R": "Coffee"; default: "Bryant Park" }
    }
    private let gymStops: [Stop] = [
        Stop(name: "Home", time: "6:40", symbol: "house.fill", c: .init(latitude: 40.7448, longitude: -74.0005)),
        Stop(name: "Gym", time: "7:00", symbol: "dumbbell.fill", c: .init(latitude: 40.7466, longitude: -74.0086)),
    ]
    private let workStops: [Stop] = [
        Stop(name: "Coffee", time: "8:40", symbol: "cup.and.saucer.fill", c: .init(latitude: 40.7560, longitude: -73.9812)),
        Stop(name: "Office", time: "9:00", symbol: "briefcase.fill", c: .init(latitude: 40.7589, longitude: -73.9790)),
    ]
    private let cafeStops: [Stop] = [
        Stop(name: "Home", time: "8:10", symbol: "house.fill", c: .init(latitude: 40.7335, longitude: -73.9990)),
        Stop(name: "Coffee", time: "8:25", symbol: "cup.and.saucer.fill", c: .init(latitude: 40.7312, longitude: -73.9972)),
    ]
    /// J/K/L: a morning through Bryant Park, so trees show up close in 3D.
    private let parkStops: [Stop] = [
        Stop(name: "Home", time: "8:10", symbol: "house.fill", c: .init(latitude: 40.7511, longitude: -73.9873)),
        Stop(name: "Bryant Park", time: "8:20", symbol: "tree.fill", c: .init(latitude: 40.7536, longitude: -73.9838)),
        Stop(name: "Blue Door Coffee", time: "8:32", symbol: "cup.and.saucer.fill", c: .init(latitude: 40.7549, longitude: -73.9806)),
        Stop(name: "Office", time: "9:02", symbol: "briefcase.fill", c: .init(latitude: 40.7572, longitude: -73.9790)),
    ]
    private let cityStops: [Stop] = [
        Stop(name: "Home", time: "8:10", symbol: "house.fill", c: .init(latitude: 40.7489, longitude: -73.9857)),
        Stop(name: "Blue Door Coffee", time: "8:32", symbol: "cup.and.saucer.fill", c: .init(latitude: 40.7527, longitude: -73.9772)),
        Stop(name: "Office", time: "9:02", symbol: "briefcase.fill", c: .init(latitude: 40.7580, longitude: -73.9712)),
        Stop(name: "Noodle Bar", time: "12:30", symbol: "fork.knife", c: .init(latitude: 40.7614, longitude: -73.9776)),
    ]
    var body: some View {
        Map(initialPosition: position, interactionModes: []) {
            if route.count > 1 {
                if ["D", "J", "K", "L", "M", "N", "P", "Q", "R"].contains(style) {
                    // D: thick route with a white edge, close and steep, like Apple Maps directions.
                    MapPolyline(coordinates: route).stroke(.white, style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: route).stroke(Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                } else if style == "F" {
                    // F: light-to-deep blue along the day, matching the ring logo.
                    MapPolyline(coordinates: route).stroke(LinearGradient(colors: [Color(red: 0.45, green: 0.75, blue: 1), Color(red: 0.05, green: 0.3, blue: 0.85)], startPoint: .leading, endPoint: .trailing),
                                                           style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                } else {
                    MapPolyline(coordinates: route)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: style == "E" ? 6 : 5, lineCap: .round, lineJoin: .round))
                }
            }
            ForEach(stops) { s in
                if let h = heroSize {
                    if s.name == heroName {
                        Annotation("", coordinate: s.c, anchor: .bottom) {
                            ApplePin(symbol: s.symbol, color: Theme.accent, hero: h)
                        }
                    }
                } else if ["G", "H", "I", "J", "K", "L"].contains(style) {
                    // G-L: C's 3D look with the new Apple-style pin (small, theme blue, dot on the spot).
                    Annotation("", coordinate: s.c, anchor: .bottom) {
                        ApplePin(symbol: s.symbol, color: Theme.accent, big: false, dot: true)
                    }
                } else {
                Annotation(style == "B" || style == "F" ? s.time : "", coordinate: s.c) {
                    Image(systemName: s.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(Theme.accent, in: .circle)
                        .overlay(Circle().stroke(.white, lineWidth: 2.5)).shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                }
                }
            }
        }
        .mapStyle(style == "B" ? .standard(emphasis: .muted, pointsOfInterest: .excludingAll) :
                  ["C", "D", "G", "H", "I", "J", "K", "L", "M", "N", "P", "Q", "R"].contains(style) ? .standard(elevation: .realistic, pointsOfInterest: .excludingAll) :
                  style == "E" ? .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll) :
                  style == "F" ? .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll) :
                  .standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .task { await loadRoute() }
    }
    private var position: MapCameraPosition {
        let center = CLLocationCoordinate2D(latitude: 40.7552, longitude: -73.9790)
        if style == "C" { return .camera(MapCamera(centerCoordinate: center, distance: 2600, heading: 29, pitch: 55)) }
        // D: closer and steeper, looking up the route from Home.
        if style == "D" { return .camera(MapCamera(centerCoordinate: .init(latitude: 40.7545, longitude: -73.9800), distance: 1700, heading: 35, pitch: 70)) }
        // E: satellite 3D.  F: muted 3D from the other side, with times.
        // G/H/I: closer and more top-down than C, like Apple's Maps splash.
        if style == "G" { return .camera(MapCamera(centerCoordinate: center, distance: 1900, heading: 29, pitch: 40)) }
        if style == "H" { return .camera(MapCamera(centerCoordinate: center, distance: 1600, heading: 29, pitch: 30)) }
        if style == "I" { return .camera(MapCamera(centerCoordinate: center, distance: 2000, heading: 0, pitch: 18)) }
        // J/K/L: H, zoomed right in like Apple Maps up close (trees, detailed 3D), route in view.
        // Lower pitch than before so buildings don't hide the route on the street.
        let park = CLLocationCoordinate2D(latitude: 40.7534, longitude: -73.9836)
        if style == "J" { return .camera(MapCamera(centerCoordinate: park, distance: 1200, heading: 29, pitch: 35)) }
        if style == "K" { return .camera(MapCamera(centerCoordinate: park, distance: 850, heading: 29, pitch: 40)) }
        if style == "P" { return .camera(MapCamera(centerCoordinate: .init(latitude: 40.7466, longitude: -74.0086), distance: 650, heading: 250, pitch: 45)) }
        if style == "Q" { return .camera(MapCamera(centerCoordinate: .init(latitude: 40.7589, longitude: -73.9790), distance: 750, heading: 29, pitch: 45)) }
        if style == "R" { return .camera(MapCamera(centerCoordinate: .init(latitude: 40.7312, longitude: -73.9972), distance: 600, heading: 20, pitch: 45)) }
        if style == "L" || style == "M" || style == "N" { return .camera(MapCamera(centerCoordinate: park, distance: 600, heading: 60, pitch: 45)) }
        if style == "E" { return .camera(MapCamera(centerCoordinate: center, distance: 2400, heading: 29, pitch: 58)) }
        if style == "F" { return .camera(MapCamera(centerCoordinate: center, distance: 2800, heading: 210, pitch: 55)) }
        return .region(MKCoordinateRegion(center: center, span: .init(latitudeDelta: 0.021, longitudeDelta: 0.021)))
    }
    private func loadRoute() async {
        var all: [CLLocationCoordinate2D] = []
        for (a, b) in zip(stops, stops.dropFirst()) {
            let r = MKDirections.Request()
            r.source = MKMapItem(placemark: MKPlacemark(coordinate: a.c))
            r.destination = MKMapItem(placemark: MKPlacemark(coordinate: b.c))
            r.transportType = .walking
            if let res = try? await MKDirections(request: r).calculate(), let poly = res.routes.first?.polyline {
                var pts = [CLLocationCoordinate2D](repeating: .init(), count: poly.pointCount)
                poly.getCoordinates(&pts, range: NSRange(location: 0, length: poly.pointCount))
                all += pts
            } else {
                all += [a.c, b.c]
            }
        }
        route = all
    }
}
