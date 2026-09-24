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
    /// Proposed: "White" uses Apple's light gray grouped background so the white cards stand out (like Settings).
    /// Sep 24: David picked A (keep the light gray grouped look), so this stays off. Old preview: -background.whiteGrouped YES.
    @AppStorage("background.whiteGrouped") private var whiteGrouped = false
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
            case .white where whiteGrouped:
                Color(.systemGroupedBackground)
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
struct CapsuleSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(Value, String)]
    /// No track behind it (used inside a glass capsule).
    var plain = false
    @Namespace private var ns
    /// Preview flag pill.style = "flat" (awaiting David's OK): plain gray highlight at rest,
    /// Liquid Glass only while the pill is moving or being dragged, like the tab bar.
    @State private var moving = false
    @State private var width: CGFloat = 0
    private var flat: Bool { (UserDefaults.standard.string(forKey: "pill.style") ?? "flat") == "flat" } // Sep 24: David approved
    private var showGlass: Bool { moving || UserDefaults.standard.bool(forKey: "pill.forceMoving") }
    /// Preview flag "pill.jelly" (awaiting David's pick): while sliding, the glass lens grows past the bar
    /// and stretches wide then squishes narrow, like the Find My tab bar. A = subtle, B = like Find My, C = strong.
    @State private var stretch: CGFloat = 0
    private var jelly: String { UserDefaults.standard.string(forKey: "pill.jelly") ?? "" }
    private var jellyParams: (scale: CGFloat, maxStretch: CGFloat, damping: Double) {
        switch jelly { case "A": (1.08, 0.22, 0.7); case "B": (1.22, 0.45, 0.55); case "C": (1.32, 0.7, 0.42); default: (1.1, 0, 1) }
    }
    private var shownStretch: CGFloat {
        let forced = UserDefaults.standard.double(forKey: "pill.forceStretch")
        return forced != 0 ? forced * jellyParams.maxStretch : stretch
    }

    var body: some View {
        if UserDefaults.standard.bool(forKey: "pill.native") {
            // Preview flag "pill.native" (David 2:04: "exactly like Apple's"): the system segmented control,
            // so the Liquid Glass lens, stretch, squish and edge bounce are Apple's own.
            Picker("", selection: $selection) {
                ForEach(options, id: \.0) { value, title in Text(title).tag(value) }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .padding(plain ? 3 : 0)
        } else if plain && flat {
            flatBody
        } else if plain {
            // Inside a glass bar: the selected item is a real Liquid Glass lens that morphs between options.
            // The labels sit on top of the lens (not inside the glass), so the selected word stays sharp,
            // and it turns blue like the selected tab in the tab bar (David).
            ZStack {
                GlassEffectContainer(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(options, id: \.0) { value, _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background {
                                    if selection == value {
                                        Color.clear
                                            .glassEffect(.regular.tint(UserDefaults.standard.string(forKey: "pill.style") == "gray" ? Color.primary.opacity(0.08) : Theme.accent.opacity(0.12)).interactive(), in: .capsule) // preview flag pill.style: "gray" = neutral pill (awaiting David OK)
                                            .glassEffectID("pill", in: ns)
                                    }
                                }
                        }
                    }
                }
                HStack(spacing: 0) {
                    ForEach(options, id: \.0) { value, title in
                        Button { withAnimation(.snappy) { selection = value } } label: {
                            Text(title).font(.subheadline.weight(.semibold))
                                .foregroundStyle(selection == value ? Theme.accent : Color.primary)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == value ? .isSelected : [])
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(3)
        } else {
            solid
        }
    }

    private func pick(_ value: Value) {
        moving = true
        if !jelly.isEmpty {
            let from = options.firstIndex { $0.0 == selection } ?? 0
            let to = options.firstIndex { $0.0 == value } ?? 0
            let p = jellyParams
            withAnimation(.easeOut(duration: 0.12)) { stretch = min(p.maxStretch, CGFloat(abs(to - from)) * p.maxStretch * 0.5) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(.spring(response: 0.45, dampingFraction: p.damping)) { stretch = 0 }
            }
            withAnimation(.spring(response: 0.4, dampingFraction: p.damping)) { selection = value }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation(.easeOut(duration: 0.25)) { moving = false } }
            return
        }
        withAnimation(.snappy) { selection = value }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation(.easeOut(duration: 0.2)) { moving = false } }
    }

    private var flatBody: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                Button { pick(value) } label: {
                    Text(title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == value ? Theme.accent : Color.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background {
                            if selection == value {
                                ZStack {
                                    Capsule().fill(Color.primary.opacity(showGlass ? 0 : 0.09))
                                    if showGlass { Color.clear.glassEffect(.regular.interactive(), in: .capsule) }
                                }
                                .scaleEffect(x: showGlass ? jellyParams.scale * (1 + shownStretch) : 1,
                                             y: showGlass ? jellyParams.scale * (1 - shownStretch * 0.28) : 1)
                                .matchedGeometryEffect(id: "flatPill", in: ns)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(3)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { g in
                    guard width > 0, !options.isEmpty else { return }
                    if !moving { withAnimation(.snappy) { moving = true } }
                    let i = min(max(Int(g.location.x / (width / CGFloat(options.count))), 0), options.count - 1)
                    if !jelly.isEmpty {
                        let p = jellyParams
                        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: p.damping)) {
                            stretch = min(p.maxStretch, abs(g.velocity.width) / 2500 * p.maxStretch)
                        }
                    }
                    if options[i].0 != selection { withAnimation(jelly.isEmpty ? .snappy : .spring(response: 0.4, dampingFraction: jellyParams.damping)) { selection = options[i].0 } }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.45, dampingFraction: jellyParams.damping)) { stretch = 0 }
                    withAnimation(.easeOut(duration: 0.25).delay(jelly.isEmpty ? 0 : 0.3)) { moving = false }
                }
        )
    }

    private var solid: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                Button { withAnimation(.snappy) { selection = value } } label: {
                    Text(title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == value ? Theme.accent : Color.primary)
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
    /// Preview flag "notifications.style": now = opens iOS Settings (old); A/B/C = in-app page versions.
    @AppStorage("notifications.style") private var notifStyle = "B1"  // David picked A (sections, plain on/off), Sep 24
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage(CheckInService.enabledKey) private var checkIns = false
    /// Sep 24: David approved the "Show Symbols" switch (on = C, off = A).
    @AppStorage("symbols.preview") private var symbolsPreview = true
    @AppStorage("symbols.show") private var showSymbols = true
    /// Preview flag "settings.noHeaders" (awaiting David's OK): no section titles, just space, like iOS Settings.
    @AppStorage("privacy.row") private var privacyRow = true
    @AppStorage("settings.noHeaders") private var noHeaders = true // Sep 24: David approved
    @ViewBuilder private func profileHeader(_ title: String) -> some View {
        if noHeaders { Color.clear.frame(height: 14) } else { SectionHeader(title) }
    }
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TabTitle("Profile")
                NavigationLink { if auth.isSignedIn { AccountView() } else { PrivacyView() } } label: {
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
                        if symbolsPreview {
                            Divider().padding(.leading, 57)
                            HStack(spacing: 13) {
                                ProfileIcon(symbol: "star.fill")
                                Toggle("Show Symbols", isOn: $showSymbols).font(.body.weight(.medium))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .accessibilityIdentifier("showSymbolsToggle")
                        }
                    }
                }
                if symbolsPreview {
                    Text("Shows the blue symbols next to places and score items.")
                        .font(.footnote).helperText().padding(.horizontal, 16).padding(.top, 6)
                }
                profileHeader("Tracking")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        NavigationLink { CheckLocationView() } label: {
                            ProfileRow(symbol: "location.circle.fill", title: "Check Location", value: checkText)
                        }
                        .accessibilityIdentifier("checkLocationRow")
                        Divider().padding(.leading, 57)
                        if notifStyle == "now" {
                            Button { openSettings() } label: { ProfileRow(symbol: "bell.fill", title: "Notifications", value: "Follows · 80 score") }
                        } else {
                            NavigationLink { NotificationsView() } label: { ProfileRow(symbol: "bell.fill", title: "Notifications", value: "") }
                                .accessibilityIdentifier("notificationsRow")
                        }
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
                    .font(.footnote).helperText().padding(.horizontal, 16).padding(.top, 6)
                if SiriSupport.isAvailable {
                    profileHeader("Siri")
                    Card(padding: 0) {
                        NavigationLink { SiriCommandsView() } label: {
                            ProfileRow(symbol: "waveform", title: "Use with Siri", value: "Examples",
                                       siriMark: UserDefaults.standard.object(forKey: "profile.siriMark") as? Bool ?? true) // Sep 24: David approved ("Perfect")
                        }
                        .accessibilityIdentifier("useWithSiriRow")
                    }
                }
                profileHeader("Privacy")
                Card(padding: 0) { VStack(spacing: 0) {
                    NavigationLink { PrivacyView() } label: { ProfileRow(symbol: "lock.fill", title: "Your data", value: "On this iPhone") }
                        .simultaneousGesture(LongPressGesture(minimumDuration: 1.2).onEnded { _ in showSiriDemo = true })
                        .accessibilityIdentifier("yourDataRow")
                    // "privacy.row" (on by default; David said "Perfect" 9/24): Privacy Policy is a row in this group, no footer.
                    if privacyRow {
                        Divider().padding(.leading, 57)
                        Button { showPolicy = true } label: { ProfileRow(symbol: "hand.raised.fill", title: "Privacy Policy", value: "") }
                            .accessibilityIdentifier("privacyPolicyRow")
                    }
                } }
                if !privacyRow {
                    Text("Your places and photos stay on your iPhone. See our [Privacy Policy](dayline://privacy).")
                        .font(.footnote).helperLinkText()
                        .padding(.horizontal, 4).padding(.top, -3)
                        .environment(\.openURL, OpenURLAction { _ in showPolicy = true; return .handled })
                        .accessibilityIdentifier("privacyPolicyLink")
                }
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
    /// Preview flag "icons.tile" (David picks): A = flat solid tile, white glyph (default, like iOS Settings);
    /// B = light tint tile, colored glyph; C = colored glyph only, no tile.
    @AppStorage("icons.tile") private var tile = "A"
    /// Preview flag "profile.tile" (David picks, Sep 24 demo): A = colored tile (default); "blue" = bold blue symbol, no tile (like Day score).
    @AppStorage("profile.tile") private var profileTile = "A"
    var body: some View {
        if profileTile == "blue" {
            Image(systemName: symbol).font(.title3.weight(.bold)).foregroundStyle(Theme.accent)
                .frame(width: size, height: size)
        } else {
            tiled
        }
    }
    @ViewBuilder private var tiled: some View {
        switch tile {
        case "B":
            Image(systemName: symbol).font(.scaled(size: size * 0.5, weight: .semibold)).minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(color)
                .frame(width: size, height: size)
                .background(color.opacity(0.15), in: .rect(cornerRadius: size * 0.24, style: .continuous))
        case "C", "C2":
            Image(systemName: symbol).font(.scaled(size: size * 0.62, weight: .medium)).minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(color)
                .frame(width: size, height: size)
        case "A3":
            Image(systemName: symbol).font(.scaled(size: size * 0.6, weight: .medium)).minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(color, in: .rect(cornerRadius: size * 0.24, style: .continuous))
        default:
            Image(systemName: symbol).font(.scaled(size: size * 0.5, weight: .semibold)).minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(.white)
                .frame(width: size, height: size)
                // Flat solid fill like iOS Settings (David: no 3D gradient look).
                .background(color, in: .rect(cornerRadius: size * 0.24, style: .continuous))
        }
    }
}

struct ProfileRow: View {
    var symbol: String
    var title: String
    var value: String
    var siriMark = false
    var body: some View {
        HStack(spacing: 13) {
            if siriMark {
                // The Siri mark David picked (demo-20 A), white on the same blue tile as the other rows.
                SiriMark(color: .white).padding(5)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent, in: .rect(cornerRadius: 30 * 0.24, style: .continuous))
            } else {
                ProfileIcon(symbol: symbol)
            }
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
    /// Preview flag "yourData.style" (David picks): now = card; A = gray note on top, button at the bottom, alert;
    /// B = same layout, bottom action sheet; C = note under the button, both at the bottom, action sheet.
    @AppStorage("yourData.style") private var style = "A"  // David picked A (Sep 24)
    private let storedText = "Your places, route, photos and notes are kept on this iPhone. Voice notes are turned into text on the device. With Back Up Timeline on, a copy is kept in your own iCloud."
    private let deleteText = "Deletes your account, your iCloud backup and everything Dayline saved on this iPhone. This can't be undone."

    var body: some View {
        if style == "now" { classic } else { simple }
    }

    private var deleteButton: some View {
        Card(padding: 0) {
            Button(role: .destructive) { confirmDelete = true } label: {
                Text("Delete Account & Backup").foregroundStyle(.red).frame(maxWidth: .infinity).frame(minHeight: 52)
            }
            .accessibilityIdentifier("deleteAccount")
        }
    }

    private var simple: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if style != "C" {
                        Text(storedText).font(.footnote).helperText().padding(.horizontal, 16)
                    }
                    Spacer(minLength: 24)
                    deleteButton
                    Text(style == "C" ? storedText + " " + deleteText : deleteText)
                        .font(.footnote).helperText().padding(.horizontal, 16)
                }
                .padding(18)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
        }
        .background(AppBackgroundView())
        .navigationTitle("Your data")
        .backgroundNavBar()
        .alert("Delete Account & Backup?", isPresented: Binding(get: { confirmDelete && style == "A" }, set: { confirmDelete = $0 })) {
            Button("Delete", role: .destructive) { Task { await deleteEverything() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your account, iCloud backup, timeline, journal and photos will be deleted. This can't be undone.") }
        .confirmationDialog("Your account, iCloud backup, timeline, journal and photos will be deleted. This can't be undone.",
                            isPresented: Binding(get: { confirmDelete && style != "A" }, set: { confirmDelete = $0 }), titleVisibility: .visible) {
            Button("Delete Account & Backup", role: .destructive) { Task { await deleteEverything() } }
            Button("Cancel", role: .cancel) {}
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var classic: some View {
        ScrollView {
          VStack(spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Stored on this iPhone", systemImage: "iphone").font(.headline)
                    Text("Your places, route, photos and notes are kept on this iPhone. Voice notes are turned into text on the device. With Back Up Timeline on, a copy is kept in your own iCloud.")
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
            Text("Deletes your account, your iCloud backup and everything Dayline saved on this iPhone. This can't be undone.")
                .font(.footnote).helperText().padding(.horizontal, 4)
          }
          .padding(18)
        }
        .background(AppBackgroundView())
        .navigationTitle("Your data")
        .backgroundNavBar()
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
    /// Preview flag "check.preview" (awaiting David's pick): map thumbnails of the day route at each rate.
    /// A = thumbnail at the left of each row, B = three big previews on top (like wallpapers), C = thumbnail at the right.
    /// David chose C (2:18, relayed): phone on the right of each row. Now the default.
    @AppStorage("check.preview") private var preview = "C"
    @AppStorage("check.big") private var bigStyle = ""
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
                if preview == "B" {
                    HStack(spacing: 12) {
                        ForEach(options, id: \.0) { o in
                            VStack(spacing: 18) {
                                thumb(o.0, w: 96, h: 0)
                                    .overlay(alignment: .bottom) {
                                        if minutes == o.0 { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white, Theme.accent).offset(y: 12) }
                                    }
                                Text(o.1).font(.footnote.weight(.semibold)).foregroundStyle(minutes == o.0 ? Theme.accent : .primary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.bottom, 18)
                }
                SectionHeader("Check every").padding(.bottom, 6)
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                            Button {
                                minutes = o.0
                                LocationService.shared.setCheckMinutes(o.0)
                            } label: {
                                HStack(spacing: 12) {
                                    if preview == "A" { thumb(o.0, w: 44, h: 0) }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(o.1).font(.body).foregroundStyle(.primary)
                                        Text(o.2).font(.subheadline).foregroundStyle(.secondary)
                                        Text("About \(o.3) battery a day").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if minutes == o.0 {
                                        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
                                    }
                                    if preview == "C" { thumb(o.0, w: 44, h: 0) }
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
        .sheet(item: Binding(get: { (bigStyle.isEmpty || bigStyle == "B") ? enlarged.map { IntervalID(id: $0) } : nil }, set: { enlarged = $0?.id })) { item in
            if bigStyle == "B" {
                IntervalRouteCard(minutes: item.id, style: "B") { enlarged = nil }
                    .presentationDetents([.fraction(0.62)])
                    .presentationDragIndicator(.visible)
            } else {
                IntervalRouteSheet(minutes: item.id)
            }
        }
        .overlay {
            if let m = enlarged, bigStyle == "A" || bigStyle == "C" {
                ZStack {
                    Color.black.opacity(bigStyle == "C" ? 0.55 : 0.3).ignoresSafeArea()
                        .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { enlarged = nil } }
                    if bigStyle == "A" {
                        IntervalRouteCard(minutes: m, style: "A") { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { enlarged = nil } }
                            .frame(height: 520)
                            .background(Color(.systemBackground), in: .rect(cornerRadius: 34))
                            .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
                            .padding(.horizontal, 20)
                    } else {
                        IntervalRouteCard(minutes: m, style: "C") { enlarged = nil }
                            .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { enlarged = nil } }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .accessibilityIdentifier("bigCard")
            }
        }
        .navigationTitle("Check Location")
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct IntervalID: Identifiable { let id: Int }

/// Full privacy policy, opened from the link under Profile > Privacy.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    private let sections: [(String, String)] = [
        ("The short version", "Your places, routes, photos and notes stay on your iPhone. We don\u{2019}t sell your data and there are no ads."),
        ("What Dayline collects", "Location, to build your timeline of places and routes. Photos you allow, to show them on your day. Microphone, only while you record a voice note; it\u{2019}s turned into text on your iPhone."),
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
    /// Preview flag "text.gray" (awaiting David's OK): on dark backgrounds use Apple's dark-mode gray
    /// (secondaryLabel, 60% light gray) instead of blue.
    @AppStorage("text.gray") private var grayText = true // Sep 24: David approved
    private var darkHelper: AnyShapeStyle {
        grayText ? AnyShapeStyle(Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.6)) : AnyShapeStyle(Theme.accent)
    }

    func body(content: Content) -> some View {
        let dark = BackgroundTone.isDark(presetRaw: presetRaw, styleRaw: styleRaw, scheme: scheme)
        switch role {
        // Small gray helper text (section headers, footers): blue on dark backgrounds, gray otherwise.
        case .helper: content.foregroundStyle(dark ? darkHelper : AnyShapeStyle(.secondary))
        // Footer text with a link: helper color, and the link turns white on dark backgrounds.
        case .link: content.foregroundStyle(dark ? darkHelper : AnyShapeStyle(.secondary)).tint(dark ? (grayText ? Theme.accent : .white) : Theme.accent)
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


/// Profile > Notifications: which notifications Dayline sends, as native switches.
/// Versions (preview flag "notifications.style"): A = Settings-style rows with icon tiles and a note under each group;
/// B = plain switches, one group, one note; C = like iOS Settings > Notifications: Allow Notifications on top, then the types.
struct NotificationsView: View {
    @AppStorage("notifications.style") private var style = "B1"  // David picked (demo-18 A)
    @AppStorage("notify.follows") private var follows = true
    @AppStorage("notify.score80") private var score80 = true
    @AppStorage(CheckInService.enabledKey) private var checkIns = false
    @AppStorage("notify.all") private var all = true
    @AppStorage("notify.sleepQ") private var sleepQ = true
    @AppStorage("notify.morningQ") private var morningQ = true
    @AppStorage("notify.lowScore") private var lowScore = true
    @AppStorage("notify.streakEnding") private var streakEnding = false
    @AppStorage("notify.friendPassed") private var friendPassed = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch style {
                case "B": versionB
                case "C": versionC
                case "B1", "B2", "B3": sectioned(style)
                default: versionA
                }
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

    private func tileRow(_ symbol: String, _ title: String, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 13) {
            ProfileIcon(symbol: symbol)
            Toggle(title, isOn: on).font(.body)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
    }
    private func plainRow(_ title: String, _ on: Binding<Bool>) -> some View {
        Toggle(title, isOn: on).font(.body).padding(.horizontal, 16).padding(.vertical, 7)
    }
    private func note(_ t: String) -> some View {
        Text(t).font(.footnote).helperText().padding(.horizontal, 16).padding(.bottom, 14)
    }
    private var group: some Shape { .rect(cornerRadius: Theme.cardRadius, style: .continuous) }

    @ViewBuilder private var versionA: some View {
        VStack(spacing: 0) {
            tileRow("person.2.fill", "Follow Requests", $follows)
            Divider().padding(.leading, 57)
            tileRow("star.fill", "Score Reaches 80", $score80)
        }
        .background(Color(.secondarySystemGroupedBackground), in: group)
        note("Get a notification when someone asks to see your streak, and when today's score reaches 80.")
        VStack(spacing: 0) { tileRow("questionmark.bubble.fill", "Check-in Questions", $checkIns) }
            .background(Color(.secondarySystemGroupedBackground), in: group)
        note("Quick yes/no questions, like \u{201C}Going to sleep now?\u{201D}, when Dayline isn't sure. Answer right from the notification.")
    }

    /// Round 3 (David: only on/off per kind, sounds and banners stay in the Settings app). B1 plain, B2 with a line under each, B3 with icons.
    private struct Kind { var symbol: String; var color: Color; var title: String; var sub: String; var on: Binding<Bool> }
    private func header(_ t: String) -> some View {
        Text(t).font(.subheadline.weight(.semibold)).helperText().padding(.horizontal, 16).padding(.top, 4)
    }
    private func kindGroup(_ v: String, _ kinds: [Kind]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(kinds.enumerated()), id: \.offset) { i, k in
                if i > 0 { Divider().padding(.leading, v == "B3" ? 57 : 16) }
                HStack(spacing: 13) {
                    if v == "B3" { ProfileIcon(symbol: k.symbol, color: k.color) }
                    Toggle(isOn: k.on) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(k.title).font(.body)
                            if v == "B2" { Text(k.sub).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
                .padding(.horizontal, v == "B3" ? 14 : 16).padding(.vertical, v == "B2" ? 9 : 7)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: group)
    }
    @ViewBuilder private func sectioned(_ v: String) -> some View {
        header("Questions")
        kindGroup(v, [Kind(symbol: "moon.fill", color: .indigo, title: "Going to Sleep?", sub: "A yes/no question at night", on: $sleepQ),
                      Kind(symbol: "sun.max.fill", color: .orange, title: "Up Already?", sub: "A yes/no question in the morning", on: $morningQ)])
        if v != "B2" { note("Press and hold a question to answer Yes or No.") } else { Spacer().frame(height: 8) }
        header("Day Score")
        kindGroup(v, [Kind(symbol: "star.fill", color: .green, title: "You Reached 80", sub: "When your day score hits 80", on: $score80),
                      Kind(symbol: "exclamationmark", color: .red, title: "Low Score Reminder", sub: "Around 5 PM if your score is still low", on: $lowScore),
                      Kind(symbol: "flame.fill", color: Theme.accent, title: "Streak Ending Soon", sub: "In the evening if you're not at 80 yet", on: $streakEnding)])
        if v == "B3" { note("The reminder comes in the late afternoon if your score is still low.") } else { Spacer().frame(height: 8) }
        header("Friends")
        kindGroup(v, [Kind(symbol: "person.badge.plus", color: Theme.accent, title: "Follow Requests", sub: "When someone asks to see your streak", on: $follows),
                      Kind(symbol: "arrow.up.right", color: .teal, title: "Friend Passed You", sub: "When a friend beats your streak", on: $friendPassed)])
        note("Sounds and banners are in the Settings app.")
    }

    @ViewBuilder private var versionB: some View {
        VStack(spacing: 0) {
            plainRow("Follow Requests", $follows)
            Divider().padding(.leading, 16)
            plainRow("Score Reaches 80", $score80)
            Divider().padding(.leading, 16)
            plainRow("Check-in Questions", $checkIns)
        }
        .background(Color(.secondarySystemGroupedBackground), in: group)
        note("Choose what Dayline can notify you about. Check-in questions are quick yes/no questions you answer from the notification.")
    }

    @ViewBuilder private var versionC: some View {
        VStack(spacing: 0) { plainRow("Allow Notifications", $all) }
            .background(Color(.secondarySystemGroupedBackground), in: group)
        note("Turn off to stop all Dayline notifications.")
        if all {
            Text("NOTIFY ME ABOUT").font(.footnote).helperText().padding(.horizontal, 16)
            VStack(spacing: 0) {
                plainRow("Follow Requests", $follows)
                Divider().padding(.leading, 16)
                plainRow("Score Reaches 80", $score80)
                Divider().padding(.leading, 16)
                plainRow("Check-in Questions", $checkIns)
            }
            .background(Color(.secondarySystemGroupedBackground), in: group)
            .padding(.bottom, 14)
        }
        VStack(spacing: 0) {
            Button { if let u = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(u) } } label: {
                HStack { Text("Sounds and Banners").foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
                    .padding(.horizontal, 16).frame(minHeight: 50)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: group)
        note("Opens iOS Settings for Dayline's sounds, banners and badges.")
    }
}
