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
            .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
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
    /// Preview flag "rings.thick": thick proportions like the Streak ring (~17% of the diameter). Off until David approves.
    var lineWidthOverride: CGFloat? = nil
    var size: CGFloat = 88
    /// Color by pace (Today card). "ring.pace" sets how "behind" looks (default B):
    /// A = whole ring orange, B = blue blending into orange along the fill, C = blue fill plus an orange arc up to where you should be.
    /// Points still counting against you today (ScoreEngine.Pace.net). nil = not colored by pace.
    var lost: Int? = nil
    /// How well it's going, 0...1 (ScoreEngine.Pace.good): the darker the blue, the better it's going.
    var good: Double? = nil
    @AppStorage("rings.thick") private var thick = false
    @AppStorage("ring.pace") private var paceStyle = "B"
    private var lineWidth: CGFloat { lineWidthOverride ?? (thick ? (size * 0.17).rounded() : (size >= 120 ? 20 : 14)) }  // 14 pt small, 20 pt large
    private var behind: Bool { !paceStyle.isEmpty && (lost ?? 0) >= 5 }
    /// How far the day has slipped, 0...1: the more points are out of reach, the more orange.
    /// "ring.shade": "" (default) = by points lost (30 lost = darkest).
    /// B / C = by the best score still possible today: 80 or more = lightest orange (a small miss, like the gym),
    /// 75 very light, 50 darker, 20 very dark. Catching up (make-up points) moves it back toward blue.
    /// C also starts the orange from a paler, almost peach tone.
    /// B is the default. Its orange never gets darker than at "best still 75"; that is the darkest allowed.
    @AppStorage("ring.shade") private var shade = "B"
    private static let maxSlipB = 5.0 / 60
    private var slip: Double {
        guard !shade.isEmpty else { return min(1, Double(lost ?? 0) / 30) }
        let best = 100 - Double(lost ?? 0)
        let s = max(0, min(1, (80 - best) / 60))
        return shade == "B" ? min(s, Self.maxSlipB) : s
    }
    /// On track: deeper blue the better it's going.
    private var blueEnd: Color {
        guard let good, !paceStyle.isEmpty else { return Theme.accent }
        let t = max(0, min(1, (good - 0.5) / 0.5))
        return Theme.ringStart.mix(with: Theme.accent, by: 0.45 + 0.55 * t).mix(with: Color(red: 0.0, green: 0.22, blue: 0.62), by: 0.4 * t)
    }
    private static let deepOrange = Color(red: 0.72, green: 0.22, blue: 0.0)
    private var colors: [Color] {
        guard behind else { return [Theme.ringStart, blueEnd] }
        switch paceStyle {
        case "A": return [Color.orange.mix(with: .white, by: 0.35), .orange]
        case "B": return [Theme.ringStart, Theme.accent, .orange, Color(red: 0.85, green: 0.35, blue: 0.0)]
        default: return [Theme.ringStart, Theme.accent]
        }
    }
    /// B behind: light blue -> darker blue -> orange -> darker orange, one smooth blend with no hard seam.
    /// The more points slip away, the earlier along the fill the orange starts.
    /// "ring.blend": 2 (default) = mostly blue with a short orange tail; the worse it's going, the darker the orange.
    /// 1 = even spread, 3 = deeper shades with a long soft middle (other options).
    @AppStorage("ring.blend") private var blend = "2"
    private var orangeMid: Color {
        switch shade {
        case "B": return Color.orange.mix(with: .white, by: 0.35 * (1 - slip)).mix(with: Self.deepOrange, by: 0.35 * slip)
        case "C": return Color(red: 1, green: 0.78, blue: 0.55).mix(with: Self.deepOrange, by: 0.5 * slip)
        default: return Color.orange.mix(with: Self.deepOrange, by: 0.35 * slip)
        }
    }
    private var orangeEnd: Color {
        switch shade {
        case "B": return Color.orange.mix(with: .white, by: 0.3 * (1 - slip)).mix(with: Self.deepOrange, by: 0.15 + 0.85 * slip)
        case "C": return Color(red: 1, green: 0.66, blue: 0.35).mix(with: Self.deepOrange, by: slip)
        default: return Color.orange.mix(with: Self.deepOrange, by: 0.3 + 0.7 * slip)
        }
    }
    /// "ring.join" (preview, "" = today's look): how blue meets orange.
    /// A = short soft fade, B = hard split with a small gap, C = a pale middle tone between them. Oranges match ring shade B.
    @AppStorage("ring.join") private var join = ""
    /// The same orange range as ring shade B (never darker than B at "best still 75").
    private var bSlip: Double { min(Self.maxSlipB, max(0, min(1, (100 - Double(lost ?? 0) <= 80 ? (80 - (100 - Double(lost ?? 0))) / 60 : 0)))) }
    private var softStart: Color { Color.orange.mix(with: .white, by: 0.35 * (1 - bSlip)).mix(with: Self.deepOrange, by: 0.35 * bSlip) }
    private var softEnd: Color { Color.orange.mix(with: .white, by: 0.3 * (1 - bSlip)).mix(with: Self.deepOrange, by: 0.15 + 0.85 * bSlip) }
    /// Where along the fill orange takes over.
    private var splitAt: Double { 0.74 - 0.12 * slip }
    private var joining: Bool { behind && paceStyle == "B" && !join.isEmpty }
    /// A finished low day (label in orange, score under 45): the ring is orange too, in the Today ring's
    /// shade-B oranges, so ring and label always match.
    private var lowDay: Bool { lost == nil && score < 45 }
    private var gradient: Gradient {
        if lowDay {
            // Same blend as the Today ring when the day slips (shade B, blend 2): light blue into blue, then
            // into orange at the end, at the darkest orange shade B allows, since the day went badly.
            let k = Self.maxSlipB
            let mid = Color.orange.mix(with: .white, by: 0.35 * (1 - k)).mix(with: Self.deepOrange, by: 0.35 * k)
            let end = Color.orange.mix(with: .white, by: 0.3 * (1 - k)).mix(with: Self.deepOrange, by: 0.15 + 0.85 * k)
            return Gradient(stops: [.init(color: Theme.ringStart, location: 0),
                                    .init(color: Theme.accent, location: 0.6 - 0.15 * k),
                                    .init(color: mid, location: 0.88 - 0.1 * k),
                                    .init(color: end, location: 1)])
        }
        if joining {
            let a = splitAt
            switch join {
            case "A":
                return Gradient(stops: [.init(color: Theme.ringStart, location: 0), .init(color: Theme.accent, location: a - 0.04),
                                        .init(color: softStart, location: a + 0.04), .init(color: softEnd, location: 1)])
            case "C":
                return Gradient(stops: [.init(color: Theme.ringStart, location: 0), .init(color: Theme.accent, location: a - 0.14),
                                        .init(color: Color(red: 0.93, green: 0.9, blue: 0.92), location: a),
                                        .init(color: softStart, location: a + 0.1), .init(color: softEnd, location: 1)])
            default:
                return Gradient(colors: [Theme.ringStart, Theme.accent])
            }
        }
        guard behind, paceStyle == "B" else { return Gradient(colors: colors) }
        let c = colors
        switch blend {
        case "2":
            return Gradient(stops: [.init(color: c[0], location: 0),
                                    .init(color: c[1], location: 0.6 - 0.15 * slip),
                                    .init(color: orangeMid, location: 0.88 - 0.1 * slip),
                                    .init(color: orangeEnd, location: 1)])
        case "3":
            return Gradient(stops: [.init(color: Color(red: 0.55, green: 0.78, blue: 1), location: 0),
                                    .init(color: Color(red: 0.0, green: 0.36, blue: 0.85), location: 0.3 - 0.1 * slip),
                                    .init(color: Color(red: 1, green: 0.6, blue: 0.2), location: 0.72 - 0.12 * slip),
                                    .init(color: Color(red: 0.8, green: 0.28, blue: 0.0), location: 1)])
        default:
            return Gradient(stops: [.init(color: c[0], location: 0),
                                    .init(color: c[1], location: 0.45 - 0.2 * slip),
                                    .init(color: c[2], location: 0.8 - 0.15 * slip),
                                    .init(color: c[3], location: 1)])
        }
    }
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            let progress = CGFloat(min(max(score, 0), 100)) / 100
            if behind && paceStyle == "C" {
                // The points you can no longer get today, right after your score.
                let target = min(1, progress + CGFloat(lost ?? 0) / 100)
                Circle().trim(from: progress, to: target)
                    .stroke(Color.orange.opacity(0.55), style: StrokeStyle(lineWidth: lineWidth * 0.45, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            // Gradient covers only the filled part, so the round start cap isn't painted
            // with the dark end color (that made a dark spot at the top).
            if joining && join == "B" {
                // Hard split: a blue arc, a small gap, then an orange arc.
                let cut = progress * CGFloat(splitAt)
                let gap = lineWidth / (.pi * size) + 0.012
                Circle()
                    .trim(from: 0, to: max(0.001, cut - gap / 2))
                    .stroke(AngularGradient(gradient: gradient, center: .center,
                                            startAngle: .zero, endAngle: .degrees(360 * max(cut, 0.01))),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: min(progress, cut + gap / 2), to: progress)
                    .stroke(AngularGradient(colors: [softStart, softEnd], center: .center,
                                            startAngle: .degrees(360 * (cut + gap / 2)), endAngle: .degrees(360 * max(progress, 0.01))),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AngularGradient(gradient: gradient, center: .center,
                                        startAngle: .zero, endAngle: .degrees(360 * max(progress, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            }
            if score > 0 {
                Circle().fill(lowDay ? Theme.ringStart : colors[0]).frame(width: lineWidth, height: lineWidth)
                    .offset(y: -size / 2)
            }
            Text("\(score)")
                .font(.scaled(size: size * 0.3, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
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

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
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
