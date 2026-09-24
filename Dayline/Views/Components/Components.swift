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

struct ScoreRing: View {
    var score: Int
    /// Preview flag "rings.thick": thick proportions like the Streak ring (~17% of the diameter). Off until David approves.
    var lineWidthOverride: CGFloat? = nil
    var size: CGFloat = 88
    @AppStorage("rings.thick") private var thick = false
    private var lineWidth: CGFloat { lineWidthOverride ?? (thick ? (size * 0.17).rounded() : (size >= 120 ? 14 : 10)) }
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            let progress = CGFloat(min(max(score, 0), 100)) / 100
            // Gradient covers only the filled part, so the round start cap isn't painted
            // with the dark end color (that made a dark spot at the top).
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: [Theme.ringStart, Theme.accent], center: .center,
                                        startAngle: .zero, endAngle: .degrees(360 * max(progress, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if score > 0 {
                Circle().fill(Theme.ringStart).frame(width: lineWidth, height: lineWidth)
                    .offset(y: -size / 2)
            }
            Text("\(score)")
                .font(.system(size: size * 0.3, weight: .bold))
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
    /// Map pins: David picked C (outlined round) on Sep 24. People initials still follow the preview flag.
    var isMapPin = false
    @AppStorage("icons.markerStyle") private var flagStyle = "circle"
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
        // David picked B (black, like iOS) on Sep 24. "A" keeps the old blue for comparison.
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
