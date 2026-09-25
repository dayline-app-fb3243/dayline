import SwiftUI

/// Apple Maps-style place pin: round colored badge with a white edge, a small tail, and (big style) a dot on the spot.
/// Map pins use the small size with the dot; the splash uses the hero size.
struct ApplePin: View {
    var symbol: String
    var color: Color
    var big = true
    /// Small size with Apple's dot under the pin.
    var dot: Bool? = nil
    /// Hero size (splash): the badge diameter in points, like the big pin on Apple's Maps splash.
    var hero: CGFloat? = nil
    var body: some View {
        if let h = hero { heroPin(h) } else { standard }
    }
    private func heroPin(_ d: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(LinearGradient(colors: [color.mix(with: .white, by: 0.25), color], startPoint: .top, endPoint: .bottom))
                Image(systemName: symbol).font(.system(size: d * 0.40, weight: .semibold)).foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: d, height: d)
            .padding(d * 0.075)
            .background(Circle().fill(.white))
            PinTail().fill(.white).frame(width: d * 0.22, height: d * 0.16).offset(y: -1)
            Circle().fill(color).frame(width: d * 0.16, height: d * 0.16)
                .padding(d * 0.045).background(Circle().fill(.white))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .padding(.top, d * 0.12)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }
    private var standard: some View {
        let d: CGFloat = big ? 46 : (dot == true ? 24 : 34)
        let showDot = dot ?? big
        return VStack(spacing: 0) {
            ZStack {
                Circle().fill(LinearGradient(colors: [color.mix(with: .white, by: 0.22), color], startPoint: .top, endPoint: .bottom))
                Image(systemName: symbol).font(.system(size: d * 0.42, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: d, height: d)
            .padding(big ? 3.5 : 2.5)
            .background(Circle().fill(.white))
            PinTail().fill(.white).frame(width: big ? 14 : 10, height: big ? 8 : 6).offset(y: -1)
            if showDot {
                Circle().fill(color).frame(width: big ? 9 : 7, height: big ? 9 : 7)
                    .padding(big ? 2.5 : 2).background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .padding(.top, big ? 5 : 3)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
    }
}

/// Photo thumbnail in the same pin shape (rounded square instead of a circle).
struct ApplePhotoPin: View {
    var image: UIImage
    var big = true
    var dot: Bool? = nil
    var body: some View {
        let d: CGFloat = big ? 50 : (dot == true ? 30 : 38)
        let showDot = dot ?? big
        VStack(spacing: 0) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: d, height: d)
                .clipShape(.rect(cornerRadius: d * 0.28))
                .padding(big ? 3.5 : 2.5)
                .background(RoundedRectangle(cornerRadius: d * 0.28 + 3).fill(.white))
            PinTail().fill(.white).frame(width: big ? 14 : 10, height: big ? 8 : 6).offset(y: -1)
            if showDot {
                Circle().fill(Theme.accent).frame(width: big ? 9 : 7, height: big ? 9 : 7)
                    .padding(big ? 2.5 : 2).background(Circle().fill(.white)).padding(.top, big ? 5 : 3)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
    }
}

struct PinTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: r.minX, y: r.minY))
        p.addQuadCurve(to: .init(x: r.midX, y: r.maxY), control: .init(x: r.midX - r.width * 0.12, y: r.minY + r.height * 0.3))
        p.addQuadCurve(to: .init(x: r.maxX, y: r.minY), control: .init(x: r.midX + r.width * 0.12, y: r.minY + r.height * 0.3))
        p.closeSubpath()
        return p
    }
}

extension PlaceCategory {
    /// Apple Maps-like category colors for pins.
    var pinColor: Color {
        switch self {
        case .home: .indigo
        case .work: .blue
        case .gym: .green
        case .food: .orange
        case .coffee: .brown
        case .outdoors: .mint
        case .shopping: .pink
        case .other: .gray
        }
    }
}
