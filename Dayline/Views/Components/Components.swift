import SwiftUI

// MARK: - Look
//
// Content sits on clean, solid cards (white in light mode, dark grey in dark mode), like the Timeline design.
// Liquid Glass is used only for floating controls (tab bar, buttons, map overlays). Those use the
// system glass, so they follow the user's Clear / Tinted Liquid Glass setting and light / dark mode.

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

extension PlaceCategory {
    /// One theme: every category is blue.
    var color: Color { Theme.accent }
}

struct CategoryIcon: View {
    var category: PlaceCategory
    var size: CGFloat = 32
    var body: some View {
        ProfileIcon(symbol: category.symbol, size: size)
    }
}

/// One set of colours for every screen and the widgets.
/// Two colours for the whole app: blue for everything, orange only for bad or negative things.
enum Theme {
    /// Corner radius of grouped cards, measured from iOS Settings (inset grouped sections).
    static let cardRadius: CGFloat = 24

    static let accent = Color.blue
    static let bad = Color.orange
    static let good = accent
    static let okay = bad
    static let low = bad
    static let journal = accent
    static let photos = accent
    static let voice = accent
    static let route = accent
    static let ring = AngularGradient(colors: [Theme.accent.opacity(0.45), .blue], center: .center)
    /// Solid (not see-through) version of the ring's light start color.
    static let ringStart = Color(red: 0.55, green: 0.76, blue: 1.0)
    /// Score label colour, used everywhere a score is shown.
    static func scoreColor(_ score: Int) -> Color { score < 45 ? bad : accent }
    /// Days scoring this or more count toward the streak.
}

/// Short status words for the Today card. 1-3 words, always one line. The phrase changes through the day
/// (every 4 hours) so it doesn't feel canned, but never flickers while you look. "status.phrase" N (screenshots) forces one.
enum StatusPhrase {
    static let onTrack = ["On track", "Good work", "Keep it up", "Nice pace", "Looking good"]
    /// "Pick it up" removed. The three new phrases rotate with the others.
    static let behind = ["Falling behind", "Catch up", "Behind pace", "Still time", "Let's go", "You've got this"]
    static let altOptions = ["Still time", "Let's go", "You've got this"]
    static func text(behind isBehind: Bool, score: Int, now: Date = .now) -> String {
        if !isBehind && score >= 90 { return "Crushing it" }
        let list = isBehind ? behind : onTrack
        let forced = UserDefaults.standard.integer(forKey: "status.phrase")
        if forced > 0 { return list[(forced - 1) % list.count] }
        let cal = Calendar.current
        let slot = (cal.ordinality(of: .day, in: .year, for: now) ?? 0) * 6 + cal.component(.hour, from: now) / 4
        return list[slot % list.count]
    }
}

struct ScoreRing: View {
    var score: Int
    var size: CGFloat = 88
    /// Points still counting against you today (ScoreEngine.Pace.net). nil = a finished day, not colored by pace.
    var lost: Int? = nil
    /// How well it's going, 0...1 (ScoreEngine.Pace.good): the darker the blue, the better it's going.
    var good: Double? = nil
    private var lineWidth: CGFloat { size >= 120 ? 20 : 14 }
    private var behind: Bool { (lost ?? 0) >= 5 }
    /// A finished day under 45 (orange label): the ring uses the same blue-to-orange blend as a slipping Today ring.
    private var lowDay: Bool { lost == nil && score < 45 }
    private static let deepOrange = Color(red: 0.72, green: 0.22, blue: 0.0)
    /// The orange never gets darker than at "best still 75".
    private static let maxSlip = 5.0 / 60
    /// How far the day has slipped, 0...1, from the best score still possible today.
    private var slip: Double {
        if lowDay { return Self.maxSlip }
        let best = 100 - Double(lost ?? 0)
        return min(max(0, min(1, (80 - best) / 60)), Self.maxSlip)
    }
    /// On track: deeper blue the better it's going.
    private var blueEnd: Color {
        guard let good else { return Theme.accent }
        let t = max(0, min(1, (good - 0.5) / 0.5))
        return Theme.ringStart.mix(with: Theme.accent, by: 0.45 + 0.55 * t).mix(with: Color(red: 0.0, green: 0.22, blue: 0.62), by: 0.4 * t)
    }
    private var orangeMid: Color { Color.orange.mix(with: .white, by: 0.35 * (1 - slip)).mix(with: Self.deepOrange, by: 0.35 * slip) }
    private var orangeEnd: Color { Color.orange.mix(with: .white, by: 0.3 * (1 - slip)).mix(with: Self.deepOrange, by: 0.15 + 0.85 * slip) }
    /// Light blue, then blue, then a short orange tail when the day slips; the worse it goes, the earlier and darker the orange.
    private var gradient: Gradient {
        guard behind || lowDay else { return Gradient(colors: [Theme.ringStart, blueEnd]) }
        return Gradient(stops: [.init(color: Theme.ringStart, location: 0),
                                .init(color: Theme.accent, location: 0.6 - 0.15 * slip),
                                .init(color: orangeMid, location: 0.88 - 0.1 * slip),
                                .init(color: orangeEnd, location: 1)])
    }
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            let progress = CGFloat(min(max(score, 0), 100)) / 100
            // The gradient covers only the filled part, so the round start cap isn't painted with the end color.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AngularGradient(gradient: gradient, center: .center,
                                        startAngle: .zero, endAngle: .degrees(360 * max(progress, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if score > 0 {
                Circle().fill(Theme.ringStart).frame(width: lineWidth, height: lineWidth)
                    .offset(y: -size / 2)
            }
            Text("\(score)")
                .font(.scaled(size: size * 0.3, weight: .bold, relativeTo: .largeTitle)).minimumScaleFactor(0.5).lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.8), value: score)
        .accessibilityElement()
        .accessibilityLabel("Day score \(score) out of 100")
    }
}

struct FactorChip: View {
    var factor: ScoreFactor
    var body: some View {
        let (symbol, color): (String, Color) = switch factor.effect {
        case .up: ("arrowtriangle.up.fill", Theme.accent)
        case .neutral: ("circle.fill", Theme.accent)
        case .pending: ("circle", Theme.bad)
        }
        Label(factor.chip ?? factor.title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .labelStyle(ChipLabelStyle())
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.14), in: .capsule)
    }
}

private struct ChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.imageScale(.small); configuration.title }
    }
}

struct Badge: View {
    var text: String
    var color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.14), in: .capsule)
    }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}


/// Preview flag "icons.markerStyle" for map pins and people initials (David picks A/B/C):
/// circle = Apple Maps/Contacts round (default), square = Settings-style rounded square, outlined = round with white ring like Apple Maps markers.
struct MarkerBackground<S: ShapeStyle>: ViewModifier {
    var fill: S
    var size: CGFloat
    /// Map pins: People initials still follow the preview flag.
    var isMapPin = false
    @AppStorage("icons.markerStyle") private var flagStyle = "outlined"  // David: round, C outlined like map pins (Sep 24)
    private var style: String { isMapPin ? "outlined" : flagStyle }
    func body(content: Content) -> some View {
        switch style {
        case "square":
            content.background(fill, in: .rect(cornerRadius: size * 0.24, style: .continuous))
        case "outlined":
            content.background(fill, in: .circle).overlay(Circle().stroke(.white, lineWidth: max(2, size * 0.08)))
        default:
            content.background(fill, in: .circle)
        }
    }
}

extension View {
    func markerBackground<S: ShapeStyle>(_ fill: S, size: CGFloat, isMapPin: Bool = false) -> some View {
        frame(width: size, height: size).modifier(MarkerBackground(fill: fill, size: size, isMapPin: isMapPin))
    }
}


enum ChromeStyle {
    static var tint: Color {
        // "A" keeps the old blue for comparison.
        switch UserDefaults.standard.string(forKey: "chrome.style") ?? "B" {
        case "A", "now": return Theme.accent
        case "C": return Color.secondary
        default: return Color.primary
        }
    }
}

/// Large title for the root of each tab, sitting right under the status bar like iOS large titles,
/// with an optional button inline on the right (David: no empty band above the title).
struct TabTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title; self.trailing = trailing
    }
    var body: some View {
        HStack(alignment: .center) {
            Text(title).font(.largeTitle.bold()).backgroundTitle()
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
        }
        .padding(.top, 2)
    }
}

extension View {
    /// Root tab screens draw their own TabTitle, so the empty navigation bar row is hidden.
    func tabRoot() -> some View { toolbar(.hidden, for: .navigationBar) }
}


extension Font {
    /// SF at a set size that still follows the iPhone's text size and Bold Text settings (Dynamic Type).
    static func scaled(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design? = nil, relativeTo style: UIFont.TextStyle = .body) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style).scaledValue(for: size), weight: weight, design: design)
    }
}


/// Screenshot-only ("-demo.rings"): Today cards for sample days, so ring shades can be compared side by side.
struct RingSamplesView: View {
    struct Sample { var title: String; var score: Int; var lost: Int; var madeUp: Int = 0; var good: Double }
    static let samples: [Sample] = [
        Sample(title: "On track", score: 62, lost: 0, good: 0.95),
        Sample(title: "Missed the gym (best 90)", score: 48, lost: 10, good: 0.7),
        Sample(title: "Best still 75", score: 44, lost: 25, good: 0.55),
        Sample(title: "Best still 50", score: 30, lost: 50, good: 0.4),
        Sample(title: "Best still 20", score: 12, lost: 80, good: 0.2),
        Sample(title: "Catching up (journaled)", score: 58, lost: 25, madeUp: 18, good: 0.75),
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ring shades").font(.largeTitle.bold()).padding(.top, 8)
                ForEach(Self.samples.indices, id: \.self) { i in
                    let x = Self.samples[i]
                    let pace = ScoreEngine.Pace(lost: x.lost, madeUp: x.madeUp, good: x.good)
                    HStack(spacing: 14) {
                        ScoreRing(score: x.score, size: 64, lost: pace.net, good: pace.good)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(x.title).font(.headline)
                            Text("Score \(x.score) · best still possible \(100 - pace.net)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12).background(.background, in: .rect(cornerRadius: 20))
                }
                Text("New words instead of \u{201C}Pick it up\u{201D}").font(.headline).padding(.top, 6)
                HStack(spacing: 8) {
                    ForEach(StatusPhrase.altOptions.indices, id: \.self) { i in
                        Text("\(i + 1). \(StatusPhrase.altOptions[i])").font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.bad).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.bad.opacity(0.14), in: .capsule)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemGroupedBackground))
    }
}
