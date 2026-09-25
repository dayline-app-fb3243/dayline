import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import WidgetKit

enum BackgroundStore {
    static var photoURL: URL {
        URL.documentsDirectory.appending(path: "background.jpg")
    }
    static func save(_ data: Data) {
        // Downscale so the background loads fast.
        guard let image = UIImage(data: data) else { return }
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        if let jpeg = resized.jpegData(compressionQuality: 0.85) {
            try? jpeg.write(to: photoURL)
            if let shared = SharedBackgroundStore.photoURL { try? jpeg.write(to: shared) }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    static func load() -> UIImage? { UIImage(contentsOfFile: photoURL.path()) }
}

/// Drop-in replacement for the plain grouped background.
struct AppBackgroundView: View {
    @AppStorage("background.preset") private var presetRaw = BackgroundPreset.system.rawValue
    @AppStorage("background.style") private var styleRaw = PhotoStyle.blur.rawValue
    @AppStorage("background.version") private var version = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SharedBackgroundCanvas(preset: BackgroundPreset(rawValue: presetRaw) ?? .system,
                               style: PhotoStyle(rawValue: styleRaw) ?? .blur,
                               photo: BackgroundStore.load())
            .id(version)
            .ignoresSafeArea()
    }
}

/// Background (design: wallpaper-gallery tiles, "+" Photo tile first).
struct BackgroundPickerView: View {
    @AppStorage("background.preset") private var presetRaw = BackgroundPreset.system.rawValue
    @AppStorage("background.style") private var styleRaw = PhotoStyle.blur.rawValue
    @AppStorage("background.version") private var version = 0
    @State private var pick: PhotosPickerItem?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Backgrounds").font(.subheadline.weight(.semibold)).helperText()
                   .padding(.leading, 16).padding(.top, 8)
                LazyVGrid(columns: columns, spacing: 14) {
                    PhotosPicker(selection: $pick, matching: .images) {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                                .aspectRatio(0.5, contentMode: .fit)
                                .overlay {
                                    Image(systemName: "plus").font(.scaled(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
                                        .frame(width: 40, height: 40).background(Color(.systemBackground), in: .circle)
                                }
                            Text("Photo").font(.caption).foregroundStyle(Theme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose a photo")
                    .accessibilityIdentifier("backgroundPhoto")

                    if presetRaw == BackgroundPreset.photo.rawValue, let image = BackgroundStore.load() {
                        tile(title: "Your photo", on: true) {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                        .id(version)
                    }
                    ForEach(BackgroundPreset.allCases.filter { $0 != .photo }) { preset in
                        Button { presetRaw = preset.rawValue } label: {
                            tile(title: preset.title, on: presetRaw == preset.rawValue) { fill(preset) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.title)
                        .accessibilityAddTraits(presetRaw == preset.rawValue ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 2)

                if presetRaw == BackgroundPreset.photo.rawValue {
                    Text("Photo style").font(.subheadline.weight(.semibold)).helperText()
                       .padding(.leading, 16).padding(.top, 14)
                    Picker("Photo style", selection: $styleRaw) {
                        ForEach(PhotoStyle.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Background")
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .onChange(of: presetRaw) { _, value in
            SharedBackgroundStore.defaults.set(value, forKey: SharedBackgroundStore.presetKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: styleRaw) { _, value in
            SharedBackgroundStore.defaults.set(value, forKey: SharedBackgroundStore.styleKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: pick) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    BackgroundStore.save(data)
                    presetRaw = BackgroundPreset.photo.rawValue
                    version += 1
                }
            }
        }
    }

    @ViewBuilder private func fill(_ preset: BackgroundPreset) -> some View {
        if preset == .system {
            LinearGradient(colors: [Color(red: 0.71, green: 0.81, blue: 0.99), Color(.systemGroupedBackground)],
                           startPoint: .top, endPoint: .bottom)
        } else {
            LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// A small phone-shaped preview: the background with two white cards on it, like the app.
    private func tile<Content: View>(title: String, on: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            Color.clear
                .aspectRatio(0.5, contentMode: .fit)
                .overlay { content() }
                .overlay {
                    GeometryReader { g in
                        VStack(spacing: g.size.height * 0.04) {
                            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.92)).frame(height: g.size.height * 0.2)
                            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.92)).frame(height: g.size.height * 0.34)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, g.size.width * 0.1).padding(.top, g.size.height * 0.14)
                    }
                }
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .overlay(alignment: .bottomTrailing) {
                    if on {
                        Image(systemName: "checkmark").font(.scaled(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Theme.accent, in: .circle).padding(6)
                    }
                }
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(on ? Theme.accent : .clear, lineWidth: 2.5))
            Text(title).font(.caption).foregroundStyle(on ? .primary : .secondary).lineLimit(1)
        }
    }
}

struct SectionHeader: View {
    var title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.subheadline.weight(.semibold)).helperText()
            .padding(.leading, 4).padding(.top, 6)
    }
}

/// Fully rounded (pill) segmented control, to match the rest of the app's shapes.
/// Day / Week / Month / Year switcher: Apple's own segmented control, so pressing and sliding the
/// selection gets the same Liquid Glass lens (lift, stretch, squish, bounce) as the tab bar.
/// Selected word in theme blue, like the selected tab.
struct CapsuleSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(Value, String)]
    var body: some View {
        let _ = segmentedSelectedTint
        Picker("", selection: $selection) {
            ForEach(options, id: \.0) { value, title in Text(title).tag(value) }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
    }
}

/// Settings: background, account.
enum Appearance: String, CaseIterable { case system = "System", light = "Light", dark = "Dark"
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}

/// The Profile tab: account, look, tracking and privacy.
struct ProfileView: View {
    @State private var showSiriDemo = false
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var location = LocationService.shared
    @AppStorage("background.preset") private var presetRaw = BackgroundPreset.system.rawValue
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage(CheckInService.enabledKey) private var checkIns = false
    /// The "Show Symbols" switch.
    @AppStorage("symbols.show") private var showSymbols = true
    /// No section titles, just space between groups, like iOS Settings.
    private func profileHeader(_ title: String) -> some View { Color.clear.frame(height: 14) }
    @Environment(\.openURL) private var openURL
    @State private var showAccount = false
    @State private var showSignIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TabTitle("Profile")
                // Signed in: account page. Signed out: the same sign-in sheet as setup, so you can sign back in.
                Button { if auth.isSignedIn { showAccount = true } else { showSignIn = true } } label: {
                    // Same shape as the Apple Account card at the top of iOS Settings.
                    Card(padding: 0) {
                        HStack(spacing: 14) {
                            if auth.isSignedIn {
                                AccountAvatar(name: auth.displayName, size: 64, photoURL: auth.photoURL)
                            } else {
                                Image(systemName: "person.crop.circle.fill").font(.scaled(size: 64)).symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Theme.accent).frame(width: 64, height: 64)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(auth.isSignedIn ? auth.displayName : "Sign In").font(.title3.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                Text(auth.isSignedIn ? "Account, Backup, and Sign-In" : "Back up your timeline and use it on other devices")
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.body.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .contentShape(.rect)
                    }
                }
                .accessibilityIdentifier("accountRow")
                profileHeader("Your Day")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        NavigationLink { YourScheduleView() } label: {
                            ProfileRow(symbol: "clock.fill", title: "Your Schedule", value: UserSchedule.current.rangeText)
                        }
                        .accessibilityIdentifier("yourScheduleRow")
                        Divider().padding(.leading, 57)
                        NavigationLink { PlacesView() } label: {
                            ProfileRow(symbol: "mappin.and.ellipse", title: "Places", value: UserSchedule.current.home == nil ? "Add Home" : "Home \u{00B7} Work")
                        }
                        .accessibilityIdentifier("placesRow")
                    }
                }
                profileHeader("Look")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        NavigationLink { BackgroundPickerView() } label: {
                            ProfileRow(symbol: "paintpalette.fill", title: "Background", value: BackgroundPreset(rawValue: presetRaw)?.title ?? "Photo")
                        }
                        .accessibilityIdentifier("backgroundRow")
                        Divider().padding(.leading, 57)
                        Menu {
                            Picker("Appearance", selection: $appearanceRaw) {
                                ForEach(Appearance.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                            }
                        } label: {
                            ProfileRow(symbol: "circle.lefthalf.filled", title: "Appearance", value: appearanceRaw)
                        }
                        Divider().padding(.leading, 57)
                        HStack(spacing: 13) {
                            if showSymbols { ProfileIcon(symbol: "star.fill") }
                            Toggle("Show Symbols", isOn: $showSymbols)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .accessibilityIdentifier("showSymbolsToggle")
                    }
                }
                Text("Shows the blue symbols next to places and score items.")
                    .font(.footnote).helperText().padding(.horizontal, 16).padding(.top, 6)
                profileHeader("Tracking")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        NavigationLink { CheckLocationView() } label: {
                            ProfileRow(symbol: "location.circle.fill", title: "Check Location", value: checkText)
                        }
                        .accessibilityIdentifier("checkLocationRow")
                        Divider().padding(.leading, 57)
                        NavigationLink { NotificationsView() } label: { ProfileRow(symbol: "bell.fill", title: "Notifications", value: "") }
                            .accessibilityIdentifier("notificationsRow")
                        Divider().padding(.leading, 57)
                        HStack(spacing: 13) {
                            ProfileIcon(symbol: "questionmark.bubble.fill")
                            Toggle("Check-in Questions", isOn: $checkIns)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .accessibilityIdentifier("checkInsToggle")
                        .onChange(of: checkIns) { _, on in if on { Task { await Notifications.requestPermission() } } }
                    }
                }
                Text("Dayline asks quick yes/no questions, like \u{201C}Going to sleep now?\u{201D}, when it isn\u{2019}t sure. Answer right from the notification. Off by default.")
                    .font(.footnote).helperText().padding(.horizontal, 16).padding(.top, 6)
                if SiriSupport.isAvailable {
                    profileHeader("Siri")
                    Card(padding: 0) {
                        NavigationLink { SiriCommandsView() } label: {
                            ProfileRow(symbol: "waveform", title: "Use with Siri", value: "Examples",
                                       siriMark: UserDefaults.standard.object(forKey: "profile.siriMark") as? Bool ?? true)
                        }
                        .accessibilityIdentifier("useWithSiriRow")
                    }
                }
                profileHeader("Privacy")
                Card(padding: 0) { VStack(spacing: 0) {
                    NavigationLink { PrivacyView() } label: { ProfileRow(symbol: "lock.fill", title: "Your data", value: "On this iPhone") }
                        .simultaneousGesture(LongPressGesture(minimumDuration: 1.2).onEnded { _ in showSiriDemo = true })
                        .accessibilityIdentifier("yourDataRow")
                    Divider().padding(.leading, 57)
                    Button { showPolicy = true } label: { ProfileRow(symbol: "hand.raised.fill", title: "Privacy Policy", value: "") }
                        .accessibilityIdentifier("privacyPolicyRow")
                } }
                if auth.isSignedIn {
                    Button { confirmSignOut = true } label: {
                        Text("Sign Out").foregroundStyle(.red).frame(maxWidth: .infinity).frame(minHeight: 52)
                            .background(Color(.secondarySystemGroupedBackground).opacity(0.9), in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
                            .contentShape(.rect)
                    }
                    .padding(.top, 12)
                    .accessibilityIdentifier("signOutRow")
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .buttonStyle(.plain)
        .background(AppBackgroundView())
        .navigationTitle("Profile")
        .tabRoot()
        .navigationDestination(isPresented: $showSiriDemo) { SiriDemoView() }
        .navigationDestination(isPresented: $showAccount) { AccountView() }
        .sheet(isPresented: $showSignIn) { ProfileSignInFlow() }
        .sheet(isPresented: $showPolicy) { PrivacyPolicyView() }
        .alert("Sign Out?", isPresented: $confirmSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) { auth.signOut() }
        } message: {
            Text("Your timeline stays on this iPhone. Sign in again anytime to back it up.")
        }
    }

    @State private var showPolicy = false
    @State private var confirmSignOut = false

    @AppStorage(LocationService.intervalKey) private var checkMinutes = 5
    private var checkText: String { checkMinutes == 1 ? "Every 1 min" : "Every \(checkMinutes) min" }

    private var locationText: String {
        if DemoData.isDemo { return "Always" }
        return switch location.authorization {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While using"
        case .denied, .restricted: "Off"
        default: "Not set"
        }
    }
    private func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
}

/// Kept for older call sites.
typealias SettingsView = ProfileView

/// Settings-style tile: white glyph on a solid blue rounded square.
struct ProfileIcon: View {
    var symbol: String
    var size: CGFloat = 30
    var color: Color = Theme.accent
    /// Flat solid tile with a white glyph, like iOS Settings.
    var body: some View {
        Image(systemName: symbol).font(.scaled(size: size * 0.5, weight: .semibold, relativeTo: .body)).minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: .rect(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct ProfileRow: View {
    @AppStorage("symbols.show") private var showSymbols = true
    var symbol: String
    var title: String
    var value: String
    var siriMark = false
    var body: some View {
        HStack(spacing: 13) {
            if siriMark && showSymbols {
                // The Siri mark, white on the same blue tile as the other rows.
                SiriMark(color: .white).padding(5)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent, in: .rect(cornerRadius: 30 * 0.24, style: .continuous))
            } else if showSymbols {
                ProfileIcon(symbol: symbol)
            }
            Text(title).foregroundStyle(.primary)
            Spacer()
            Text(value).foregroundStyle(.secondary).lineLimit(1)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(.rect)
    }
}

struct PrivacyView: View {
    @ObservedObject private var auth = AuthService.shared
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    private let storedText = "Your places, route, photos and journal are kept on this iPhone. Voice memos are turned into text on the device. With Back Up Timeline on, a copy is kept in your own iCloud."
    private var deleteText: String {
        auth.isSignedIn ? "Deletes your account, your iCloud backup and everything Dayline saved on this iPhone. This can't be undone."
                        : "Deletes everything Dayline saved on this iPhone. This can't be undone."
    }

    private var deleteButton: some View {
        Card(padding: 0) {
            Button(role: .destructive) { confirmDelete = true } label: {
                Text(auth.isSignedIn ? "Delete Account & Backup" : "Delete Data on This iPhone").foregroundStyle(.red).frame(maxWidth: .infinity).frame(minHeight: 52)
            }
            .accessibilityIdentifier("deleteAccount")
        }
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(storedText).font(.footnote).helperText().padding(.horizontal, 16)
                    Spacer(minLength: 24)
                    deleteButton
                    Text(deleteText)
                        .font(.footnote).helperText().padding(.horizontal, 16)
                }
                .padding(18)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
        }
        .background(AppBackgroundView())
        .navigationTitle("Your data")
        .backgroundNavBar()
        .alert(auth.isSignedIn ? "Delete Account & Backup?" : "Delete Data?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await deleteEverything() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(auth.isSignedIn ? "Your account, iCloud backup, timeline, journal and photos will be deleted. This can't be undone."
                                          : "Your timeline, journal and photos will be deleted. This can't be undone.") }
        .toolbarVisibility(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Profile > Check Location: pick how often Dayline saves your location.
struct CheckLocationView: View {
    @AppStorage(LocationService.intervalKey) private var minutes = 5
    /// A mini iPhone at the right of each row shows the day route at that rate; tap to zoom it up.
    @State private var enlarged: Int?
    /// Each preview is a mini iPhone screen (David: like Apple's Tips app examples), tap to enlarge.
    private func thumb(_ m: Int, w: CGFloat, h: CGFloat) -> some View {
        MiniPhoneRoute(minutes: m, width: w)
            .contentShape(.rect).onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { enlarged = m } }
            .accessibilityIdentifier("thumb-\(m)")
    }
    private let options: [(Int, String, String, String)] = [
        (1, "1 Minute", "Best tracking. Exact routes and short stops.", "12%"),
        (5, "5 Minutes", "Good tracking. Most stops, rougher routes.", "6%"),
        (10, "10 Minutes", "Basic tracking. Longer stops only.", "3%"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Check every").padding(.bottom, 6)
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                            Button {
                                minutes = o.0
                                LocationService.shared.setCheckMinutes(o.0)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(o.1).font(.body).foregroundStyle(.primary)
                                        Text(o.2).font(.subheadline).foregroundStyle(.secondary)
                                        Text("About \(o.3) battery a day").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if minutes == o.0 {
                                        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
                                    }
                                    thumb(o.0, w: 44, h: 0)
                                }
                                .padding(.horizontal, 18).padding(.vertical, 11)
                                .contentShape(.rect)
                            }
                            .accessibilityIdentifier("check-\(o.0)")
                            if i < options.count - 1 { Divider().padding(.leading, 18) }
                        }
                    }
                }
                Text("Checking more often gives a more exact timeline but uses more battery. Battery numbers are estimates for a normal day and depend on your iPhone and how much you move.")
                    .font(.footnote).helperText().padding(.horizontal, 16).padding(.top, 8)
            }
            .padding(.horizontal, 18).padding(.top, 8)
        }
        .buttonStyle(.plain)
        .background(AppBackgroundView())
        .overlay {
            if let m = enlarged {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    IntervalRouteCard(minutes: m)
                }
                .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { enlarged = nil } }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .accessibilityIdentifier("bigCard")
            }
        }
        .navigationTitle("Check Location")
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
    }
}


/// Full privacy policy, opened from the link under Profile > Privacy.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    private let sections: [(String, String)] = [
        ("The short version", "Your places, routes, photos and journal stay on your iPhone. We don\u{2019}t sell your data and there are no ads."),
        ("What Dayline collects", "Location, to build your timeline of places and routes. Photos you allow, to show them on your day. Microphone, only while you record a voice memo; it\u{2019}s turned into text on your iPhone."),
        ("What leaves your iPhone", "If Back Up Timeline is on, your timeline and journal are saved in your own iCloud account. Dayline can\u{2019}t see it. If you share with friends, they see only your streak number."),
        ("How we use it", "Only to run Dayline for you: building your timeline, backing it up and showing your streak to people you choose. We don\u{2019}t use it for ads or sell it to anyone."),
        ("Siri", "When you ask Siri about a place, Dayline answers from the data on your iPhone."),
        ("Keeping it safe", "Your iCloud backup is protected by Apple and encrypted in transit and at rest. Only you can restore it."),
        ("Your choices", "Change what Dayline can use at any time in Settings. Delete your account and backup from Profile > Your Data."),
        ("Children", "Dayline isn\u{2019}t meant for children under 13."),
        ("Changes", "If this policy changes, we\u{2019}ll show you what changed in the app."),
        ("Contact", "Questions? Email privacy@dayline.app."),
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last updated September 24, 2026").font(.subheadline).foregroundStyle(.secondary).padding(.bottom, 6)
                    ForEach(sections, id: \.0) { s in
                        Text(s.0).font(.headline).padding(.top, 14)
                        Text(s.1).font(.body)
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Privacy Policy").navigationBarTitleDisplayMode(.inline)
            .backgroundNavBar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
    }
}


extension PrivacyView {
    @MainActor
    func deleteEverything() async {
        await AuthService.shared.deleteAccount()
        try? context.delete(model: LocationSample.self)
        try? context.delete(model: Visit.self)
        try? context.delete(model: JournalEntry.self)
        try? context.delete(model: PlanItem.self)
        try? context.delete(model: DayScore.self)
        try? context.save()
        for folder in ["Voice", "Video"] {
            try? FileManager.default.removeItem(at: URL.documentsDirectory.appending(path: folder))
        }
        try? FileManager.default.removeItem(at: BackgroundStore.photoURL)
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        dismiss()
    }
}

// MARK: Text that sits right on the background (not inside a card)

/// Whether the chosen background is dark, so text sitting on it needs light/blue colors.
enum BackgroundTone {
    static let darkPresets: Set<BackgroundPreset> = [.black, .ocean, .forest, .night, .graphite, .aurora]
    static func isDark(presetRaw: String, styleRaw: String, scheme: ColorScheme) -> Bool {
        if scheme == .dark { return true }
        let preset = BackgroundPreset(rawValue: presetRaw) ?? .system
        if darkPresets.contains(preset) { return true }
        if preset == .photo, PhotoStyle(rawValue: styleRaw) == .dim { return true }
        return false
    }
}

private struct BackgroundText: ViewModifier {
    enum Role { case helper, title, link }
    var role: Role
    @AppStorage("background.preset") private var presetRaw = BackgroundPreset.system.rawValue
    @AppStorage("background.style") private var styleRaw = PhotoStyle.blur.rawValue
    @Environment(\.colorScheme) private var scheme
    /// On dark backgrounds: Apple's dark-mode gray (secondaryLabel, 60% light gray).
    private var darkHelper: AnyShapeStyle { AnyShapeStyle(Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.6)) }

    func body(content: Content) -> some View {
        let dark = BackgroundTone.isDark(presetRaw: presetRaw, styleRaw: styleRaw, scheme: scheme)
        switch role {
        // Small gray helper text (section headers, footers): light gray on dark backgrounds, gray otherwise.
        case .helper: content.foregroundStyle(dark ? darkHelper : AnyShapeStyle(.secondary))
        // Footer text with a link: helper color, and the link turns white on dark backgrounds.
        case .link: content.foregroundStyle(dark ? darkHelper : AnyShapeStyle(.secondary)).tint(Theme.accent)
        // Big titles on the background: white on dark backgrounds.
        case .title: content.foregroundStyle(dark ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        }
    }
}

private struct BackgroundNavBar: ViewModifier {
    @AppStorage("background.preset") private var presetRaw = BackgroundPreset.system.rawValue
    @AppStorage("background.style") private var styleRaw = PhotoStyle.blur.rawValue
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let dark = BackgroundTone.isDark(presetRaw: presetRaw, styleRaw: styleRaw, scheme: scheme)
        content.background(NavBarStyle(dark: dark).frame(width: 0, height: 0))
            // Black back/close buttons (David's pick) must turn white on dark backgrounds.
            .toolbarColorScheme(dark ? .dark : nil, for: .navigationBar)
    }
}

/// Makes the navigation bar (large title, back button) use light text on dark backgrounds.
private struct NavBarStyle: UIViewControllerRepresentable {
    var dark: Bool
    func makeUIViewController(context: Context) -> UIViewController { Controller() }
    func updateUIViewController(_ vc: UIViewController, context: Context) {
        (vc as? Controller)?.dark = dark
        (vc as? Controller)?.apply()
    }
    final class Controller: UIViewController {
        var dark = false
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); apply() }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); apply() }
        func apply() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let nav = self.navigationController else { return }
                nav.navigationBar.overrideUserInterfaceStyle = self.dark ? .dark : .unspecified
                // Back buttons show just the chevron (like Settings), with the title centered.
                nav.viewControllers.forEach { $0.navigationItem.backButtonDisplayMode = .minimal }
            }
        }
    }
}

extension View {
    /// Section headers and footer notes that sit on the background.
    func helperText() -> some View { modifier(BackgroundText(role: .helper)) }
    /// Footer notes that contain a link (like "Privacy Policy").
    func helperLinkText() -> some View { modifier(BackgroundText(role: .link)) }
    /// Large titles that sit on the background.
    func backgroundTitle() -> some View { modifier(BackgroundText(role: .title)) }
    /// Keeps the navigation title readable on dark backgrounds.
    func backgroundNavBar() -> some View { modifier(BackgroundNavBar()) }
}


/// Profile > Notifications: which notifications Dayline sends, one native switch per kind.
/// Sounds and banners stay in the Settings app.
struct NotificationsView: View {
    @AppStorage("notify.follows") private var follows = true
    @AppStorage("notify.score80") private var score80 = true
    @AppStorage(CheckInService.enabledKey) private var checkIns = false
    @AppStorage("notify.sleepQ") private var sleepQ = true
    @AppStorage("notify.morningQ") private var morningQ = true
    @AppStorage("notify.lowScore") private var lowScore = true
    @AppStorage("notify.streakEnding") private var streakEnding = false
    @AppStorage("notify.friendPassed") private var friendPassed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header("Questions")
                group([("Going to Sleep?", $sleepQ), ("Up Already?", $morningQ)])
                note("Press and hold a question to answer Yes or No.")
                header("Day Score")
                group([("You Reached 80", $score80), ("Low Score Reminder", $lowScore), ("Streak Ending Soon", $streakEnding)])
                Spacer().frame(height: 8)
                header("Friends")
                group([("Follow Requests", $follows), ("Friend Passed You", $friendPassed)])
                note("Sounds and banners are in the Settings app.")
            }
            .padding(18)
        }
        .background(AppBackgroundView())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .backgroundNavBar()
        .toolbarVisibility(.hidden, for: .tabBar)
        .onChange(of: checkIns) { _, on in if on { Task { await Notifications.requestPermission() } } }
        .accessibilityIdentifier("notificationsScreen")
    }

    private func header(_ t: String) -> some View {
        Text(t).font(.subheadline.weight(.semibold)).helperText().padding(.horizontal, 16).padding(.top, 4)
    }
    private func note(_ t: String) -> some View {
        Text(t).font(.footnote).helperText().padding(.horizontal, 16).padding(.bottom, 14)
    }
    private func group(_ rows: [(String, Binding<Bool>)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                if i > 0 { Divider().padding(.leading, 16) }
                Toggle(r.0, isOn: r.1).padding(.horizontal, 16).padding(.vertical, 7)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// Selected word of the system segmented control in theme blue, like the selected tab. Set once.
private let segmentedSelectedTint: Void = {
    UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(Theme.accent)], for: .selected)
}()


/// Sign in again from Profile (after signing out): the setup sign-in sheet; Email goes on to the code step.
struct ProfileSignInFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    var body: some View {
        switch step {
        case 0:
            SignInSheet(next: { dismiss() }, email: { withAnimation { step = 1 } })
        case 1:
            EmailView(next: { withAnimation { step = 2 } }, back: { withAnimation { step = 0 } })
                .presentationDetents([.large])
        default:
            EmailCodeView(next: { dismiss() }, back: { withAnimation { step = 1 } })
                .presentationDetents([.large])
        }
    }
}
