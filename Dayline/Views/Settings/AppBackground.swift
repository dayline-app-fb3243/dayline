import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Built-in backgrounds plus "your own photo". Content cards stay solid on top of any of these.
enum BackgroundPreset: String, CaseIterable, Identifiable {
    case system, white, black, gray, sky, ocean, mint, forest, lavender, rose, sunset, sand, night, graphite, aurora, photo
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Default"
        case .photo: "Your photo"
        default: rawValue.capitalized
        }
    }

    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
    var colors: [Color] {
        let c = Self.c
        switch self {
        case .system, .photo: return []
        case .white: return [.white, .white]
        case .black: return [.black, .black]
        case .gray: return [c(0.82, 0.82, 0.84), c(0.90, 0.90, 0.92)]
        case .sky: return [c(0.61, 0.77, 1.0), c(0.91, 0.94, 1.0)]
        case .ocean: return [c(0.18, 0.48, 1.0), c(0.04, 0.25, 0.69)]
        case .mint: return [c(0.66, 0.93, 0.83), c(0.93, 0.98, 0.96)]
        case .forest: return [c(0.18, 0.49, 0.36), c(0.07, 0.31, 0.23)]
        case .lavender: return [c(0.80, 0.72, 1.0), c(0.95, 0.93, 1.0)]
        case .rose: return [c(1.0, 0.70, 0.78), c(1.0, 0.91, 0.93)]
        case .sunset: return [c(1.0, 0.70, 0.54), c(1.0, 0.85, 0.78), c(0.79, 0.71, 1.0)]
        case .sand: return [c(0.91, 0.85, 0.72), c(0.97, 0.95, 0.89)]
        case .night: return [c(0.11, 0.14, 0.28), c(0.23, 0.25, 0.44)]
        case .graphite: return [c(0.28, 0.28, 0.29), c(0.11, 0.11, 0.12)]
        case .aurora: return [c(0.35, 0.78, 0.98), c(0.69, 0.32, 0.87)]
        }
    }
}

enum PhotoStyle: String, CaseIterable, Identifiable {
    case blur, sharp, dim
    var id: String { rawValue }
    var title: String { switch self { case .blur: "Soft blur"; case .sharp: "Sharp"; case .dim: "Dimmed" } }
}

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
        try? resized.jpegData(compressionQuality: 0.85)?.write(to: photoURL)
    }
    static func load() -> UIImage? { UIImage(contentsOfFile: photoURL.path()) }
}

/// Drop-in replacement for the plain grouped background.
struct AppBackgroundView: View {
    @AppStorage("background.preset") private var presetRaw = BackgroundPreset.system.rawValue
    @AppStorage("background.style") private var styleRaw = PhotoStyle.blur.rawValue
    @AppStorage("background.version") private var version = 0
    @Environment(\.colorScheme) private var scheme

    private func blob(_ color: Color, _ size: CGFloat) -> some View {
        Circle().fill(color).frame(width: size, height: size).blur(radius: 50)
    }

    var body: some View {
        let preset = BackgroundPreset(rawValue: presetRaw) ?? .system
        ZStack {
            Color(.systemGroupedBackground)
            switch preset {
            case .system:
                // Dayline's own look: soft blue light behind the solid cards.
                GeometryReader { geo in
                    ZStack {
                        blob(Color(red: 0.61, green: 0.76, blue: 1.0), 320).position(x: -80 + 160, y: -60 + 160)
                        blob(Color(red: 0.81, green: 0.88, blue: 1.0), 300).position(x: geo.size.width + 120 - 150, y: 180 + 150)
                        blob(Color(red: 0.73, green: 0.83, blue: 1.0), 320).position(x: -60 + 160, y: geo.size.height + 40 - 160)
                    }
                    .opacity(scheme == .dark ? 0.35 * 0.55 : 0.75)
                }
            case .photo:
                if let image = BackgroundStore.load() {
                    let style = PhotoStyle(rawValue: styleRaw) ?? .blur
                    Image(uiImage: image).resizable().scaledToFill()
                        .blur(radius: style == .blur ? 24 : 0)
                        .overlay(Color.black.opacity(style == .dim ? 0.35 : (scheme == .dark ? 0.25 : 0.05)))
                        .id(version)
                }
            default:
                LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(scheme == .dark && preset != .night ? 0.35 : 1)
            }
        }
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
                Text("Backgrounds").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .textCase(.uppercase).padding(.leading, 16).padding(.top, 8)
                LazyVGrid(columns: columns, spacing: 14) {
                    PhotosPicker(selection: $pick, matching: .images) {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                                .aspectRatio(0.5, contentMode: .fit)
                                .overlay {
                                    Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
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
                    Text("Photo style").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        .textCase(.uppercase).padding(.leading, 16).padding(.top, 14)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
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
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
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
        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            .padding(.leading, 4).padding(.top, 6)
    }
}

/// Fully rounded (pill) segmented control, to match the rest of the app's shapes.
struct CapsuleSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(Value, String)]
    /// No track behind it (used inside a glass capsule).
    var plain = false
    @Namespace private var ns

    var body: some View {
        if plain {
            // Inside a glass bar: the selected item is a real Liquid Glass lens that morphs between options.
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(options, id: \.0) { value, title in
                        Button { withAnimation(.snappy) { selection = value } } label: {
                            Text(title).font(.subheadline.weight(.semibold))
                                .foregroundStyle(selection == value ? Color.primary : Color.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .background {
                            if selection == value {
                                Color.clear
                                    .glassEffect(.regular.interactive(), in: .capsule)
                                    .glassEffectID("pill", in: ns)
                            }
                        }
                        .accessibilityAddTraits(selection == value ? .isSelected : [])
                    }
                }
                .padding(3)
            }
        } else {
            solid
        }
    }

    private var solid: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                Button { withAnimation(.snappy) { selection = value } } label: {
                    Text(title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == value ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background {
                            if selection == value {
                                Capsule().fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.07), in: .capsule)
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
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink { if auth.isSignedIn { AccountView() } else { PrivacyView() } } label: {
                    Card(padding: 14) {
                        HStack(spacing: 13) {
                            if auth.isSignedIn { AccountAvatar(name: auth.name, size: 52) } else { ProfileIcon(symbol: "person.fill", size: 52) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(auth.isSignedIn ? (auth.name.isEmpty ? "Your Account" : auth.name) : "Not signed in").font(.title3.weight(.semibold))
                                Text(auth.isSignedIn ? "Signed in with \(auth.provider.capitalized) \u{00B7} Backed up" : "Your timeline stays on this iPhone")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                }
                .accessibilityIdentifier("accountRow")
                SectionHeader("Your Day")
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
                SectionHeader("Look")
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
                    }
                }
                SectionHeader("Tracking")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        NavigationLink { CheckLocationView() } label: {
                            ProfileRow(symbol: "location.circle.fill", title: "Check Location", value: checkText)
                        }
                        .accessibilityIdentifier("checkLocationRow")
                        Divider().padding(.leading, 57)
                        Button { openSettings() } label: {
                            ProfileRow(symbol: "location.fill", title: "Location", value: locationText)
                        }
                        Divider().padding(.leading, 57)
                        Button { openSettings() } label: { ProfileRow(symbol: "photo.fill", title: "Photos", value: "Added to timeline") }
                        Divider().padding(.leading, 57)
                        Button { openSettings() } label: { ProfileRow(symbol: "bell.fill", title: "Notifications", value: "Follows · 80 score") }
                        Divider().padding(.leading, 57)
                        HStack(spacing: 13) {
                            ProfileIcon(symbol: "questionmark.bubble.fill")
                            Toggle("Check-in Questions", isOn: $checkIns).font(.body.weight(.medium))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .accessibilityIdentifier("checkInsToggle")
                        .onChange(of: checkIns) { _, on in if on { Task { await Notifications.requestPermission() } } }
                    }
                }
                Text("Dayline asks quick yes/no questions, like \u{201C}Going to sleep now?\u{201D}, when it isn\u{2019}t sure. Answer right from the notification. Off by default.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 6)
                if SiriSupport.isAvailable {
                    SectionHeader("Siri")
                    Card(padding: 0) {
                        NavigationLink { SiriCommandsView() } label: {
                            ProfileRow(symbol: "waveform", title: "Use with Siri", value: "Examples")
                        }
                        .accessibilityIdentifier("useWithSiriRow")
                    }
                }
                SectionHeader("Privacy")
                Card(padding: 0) {
                    NavigationLink { PrivacyView() } label: { ProfileRow(symbol: "lock.fill", title: "Your data", value: "On this iPhone") }
                        .simultaneousGesture(LongPressGesture(minimumDuration: 1.2).onEnded { _ in showSiriDemo = true })
                        .accessibilityIdentifier("yourDataRow")
                }
                Text("Your places and photos stay on your iPhone. See our [Privacy Policy](dayline://privacy).")
                    .font(.footnote).foregroundStyle(.secondary).tint(Theme.accent)
                    .padding(.horizontal, 4).padding(.top, -3)
                    .environment(\.openURL, OpenURLAction { _ in showPolicy = true; return .handled })
                    .accessibilityIdentifier("privacyPolicyLink")
                if auth.isSignedIn {
                    Button { confirmSignOut = true } label: {
                        Text("Sign Out").foregroundStyle(.red).frame(maxWidth: .infinity).frame(minHeight: 52)
                            .background(Color(.secondarySystemGroupedBackground).opacity(0.9), in: .rect(cornerRadius: 26, style: .continuous))
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
        .toolbarRole(.editor)
        .navigationDestination(isPresented: $showSiriDemo) { SiriDemoView() }
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
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.accent, in: .rect(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct ProfileRow: View {
    var symbol: String
    var title: String
    var value: String
    var body: some View {
        HStack(spacing: 13) {
            ProfileIcon(symbol: symbol)
            Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
            Spacer()
            Text(value).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
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
    var body: some View {
        ScrollView {
          VStack(spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Stored on this iPhone", systemImage: "iphone").font(.headline)
                    Text("Your places, route, photos and notes are kept on this iPhone. Voice notes are turned into text on the device. If you sign in, a backup is kept for you only.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Card(padding: 0) {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Text("Delete Account & Backup").foregroundStyle(.red).frame(maxWidth: .infinity).frame(minHeight: 52)
                }
                .accessibilityIdentifier("deleteAccount")
            }
            .padding(.top, 10)
            Text("Deletes your account, your backup and everything Dayline saved on this iPhone. This can't be undone.")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
          }
          .padding(18)
        }
        .background(AppBackgroundView())
        .navigationTitle("Your data")
        .alert("Delete Account & Backup?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await deleteEverything() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account, backup, timeline, journal and photos saved in Dayline will be deleted. This can't be undone.")
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Profile > Check Location: pick how often Dayline saves your location.
struct CheckLocationView: View {
    @AppStorage(LocationService.intervalKey) private var minutes = 5
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
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(o.1).font(.body).foregroundStyle(.primary)
                                        Text(o.2).font(.subheadline).foregroundStyle(.secondary)
                                        Text("About \(o.3) battery a day").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if minutes == o.0 {
                                        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
                                    }
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
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 8)
            }
            .padding(.horizontal, 18).padding(.top, 8)
        }
        .buttonStyle(.plain)
        .background(AppBackgroundView())
        .navigationTitle("Check Location")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Full privacy policy, opened from the link under Profile > Privacy.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    private let sections: [(String, String)] = [
        ("The short version", "Your places, routes, photos and notes stay on your iPhone. We don\u{2019}t sell your data and there are no ads."),
        ("What Dayline collects", "Location, to build your timeline of places and routes. Photos you allow, to show them on your day. Microphone, only while you record a voice note; it\u{2019}s turned into text on your iPhone."),
        ("What leaves your iPhone", "If you sign in, your name, email and an encrypted backup of your timeline are stored for you only. If you share with friends, they see only your streak number."),
        ("How we use it", "Only to run Dayline for you: building your timeline, backing it up and showing your streak to people you choose. We don\u{2019}t use it for ads or sell it to anyone."),
        ("Siri", "When you ask Siri about a place, Dayline answers from the data on your iPhone."),
        ("Keeping it safe", "Your backup is encrypted in transit and at rest. Only you can restore it."),
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
