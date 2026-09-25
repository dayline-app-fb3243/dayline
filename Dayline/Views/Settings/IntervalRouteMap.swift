import SwiftUI
import MapKit

/// Map preview for Profile > Check Location: the same demo walk, drawn from one point every N minutes,
/// so you can see how rough the day route gets at each check rate.
struct IntervalRouteMap: View {
    var minutes: Int
    var interactive = false
    /// Show a dot at every location check, so you can see how precise each rate is.
    var dots = false
    @State private var route: [CLLocationCoordinate2D] = []
    private static let stops: [CLLocationCoordinate2D] = [
        .init(latitude: 40.7489, longitude: -73.9857), .init(latitude: 40.7527, longitude: -73.9772),
        .init(latitude: 40.7580, longitude: -73.9712), .init(latitude: 40.7614, longitude: -73.9776),
    ]
    /// A walk of ~50 minutes; keep one point per `minutes`.
    private var sampled: [CLLocationCoordinate2D] {
        guard route.count > 2 else { return route }
        let perMinute = Double(route.count) / 50
        let step = max(1, Int(Double(minutes) * perMinute))
        var out = stride(from: 0, to: route.count, by: step).map { route[$0] }
        if let last = route.last { out.append(last) }
        return out
    }
    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: .init(latitude: 40.7552, longitude: -73.9790),
                                                         span: .init(latitudeDelta: 0.017, longitudeDelta: 0.017))),
            interactionModes: interactive ? .all : []) {
            // A dot for every check, no line.
            checkDots(size: 9, ring: 2.5)
            // Same blue Apple-style pins as every other map, icon = place type.
            ForEach(Array(Self.stops.enumerated()), id: \.offset) { i, c in
                Annotation("", coordinate: c, anchor: .bottom) {
                    ApplePin(symbol: ["house.fill", "cup.and.saucer.fill", "briefcase.fill", "fork.knife"][i], color: Theme.accent, big: false, dot: true)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .allowsHitTesting(interactive)
        .task { await load() }
    }
    @MapContentBuilder private func checkDots(size: CGFloat, ring: CGFloat) -> some MapContent {
        ForEach(Array(sampled.enumerated()), id: \.offset) { _, c in
            Annotation("", coordinate: c) {
                Circle().fill(Theme.accent).frame(width: size, height: size).padding(ring).background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
            }
        }
    }
    private func load() async {
        var all: [CLLocationCoordinate2D] = []
        for (a, b) in zip(Self.stops, Self.stops.dropFirst()) {
            let r = MKDirections.Request()
            r.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
            r.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
            r.transportType = .walking
            if let res = try? await MKDirections(request: r).calculate(), let poly = res.routes.first?.polyline {
                // Resample to evenly spaced points so "one point per minute" means something.
                var pts = [CLLocationCoordinate2D](repeating: .init(), count: poly.pointCount)
                poly.getCoordinates(&pts, range: NSRange(location: 0, length: poly.pointCount))
                all += Self.resample(pts, spacing: 12)
            } else { all += [a, b] }
        }
        route = all
    }
    private static func resample(_ pts: [CLLocationCoordinate2D], spacing: Double) -> [CLLocationCoordinate2D] {
        guard pts.count > 1 else { return pts }
        var out = [pts[0]]; var carry = 0.0
        for (a, b) in zip(pts, pts.dropFirst()) {
            let d = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            var t = spacing - carry
            while t <= d {
                let f = t / d
                out.append(.init(latitude: a.latitude + (b.latitude - a.latitude) * f, longitude: a.longitude + (b.longitude - a.longitude) * f))
                t += spacing
            }
            carry = d - (t - spacing)
        }
        return out
    }
}

/// Tapping a mini iPhone zooms it up big, with a dot at each check.
struct IntervalRouteCard: View {
    var minutes: Int
    private var checks: String { minutes == 1 ? "A dot for every check, once a minute" : "A dot for every check, every \(minutes) minutes" }
    var body: some View {
        VStack(spacing: 18) {
            MiniPhoneRoute(minutes: minutes, width: 250, dots: true)
            Text(checks).font(.subheadline).foregroundStyle(.white)
        }
    }
}

/// A tiny iPhone (frame, Dynamic Island, status bar) showing the day map at a check rate, like the examples in Apple's Tips app.
/// Drawn at a fixed base size and scaled down, so the details stay in proportion.
struct MiniPhoneRoute: View {
    var minutes: Int
    var width: CGFloat
    var dots = false
    /// Drawn at real size when shown big (a scaled-up Map dropped its route line and pins), scaled down when small.
    private var base: CGFloat { max(200, width) }
    var body: some View {
        let h = base * 2.17
        ZStack(alignment: .top) {
            IntervalRouteMap(minutes: minutes, dots: dots)
                .frame(width: base - 12, height: h - 12)
                .clipShape(.rect(cornerRadius: 30))
            // Status bar
            HStack {
                Text("9:41").font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "cellularbars")
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100percent")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 24).padding(.top, 17)
            // Dynamic Island
            Capsule().fill(.black).frame(width: 62, height: 18).padding(.top, 14)
            // "Every N min" label, like the app's map pill
            VStack {
                Spacer()
                Text("Every \(minutes) min").font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.regularMaterial, in: .capsule)
                    .padding(.bottom, 22)
            }
        }
        .frame(width: base - 12, height: h - 12)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 36).fill(.black))
        .overlay(RoundedRectangle(cornerRadius: 36).stroke(Color.gray.opacity(0.5), lineWidth: 1.5))
        .frame(width: base, height: h)
        .scaleEffect(width / base)
        .frame(width: width, height: width * 2.17)
    }
}
