import SwiftUI
import MapKit

/// Small "DAYLINE" line at the top of every Siri card, like the approved iOS 27 mockup.
struct SiriAppLine: View {
    var body: some View {
        HStack(spacing: 6) {
            AppMark(size: 18)
            Text("DAYLINE").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
        }
    }
}

/// Black card shell shared by all Dayline Siri cards.
struct SiriCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SiriAppLine()
            content
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.black)
    }
}

struct SiriScoreRing: View {
    var value: Int
    var color: Color
    var size: CGFloat = 78
    var label: String? = nil
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: 9)
            Circle().trim(from: 0, to: CGFloat(min(max(value, 0), 100)) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(label ?? "\(value)").font(.scaled(size: size * 0.3, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
        }
        .frame(width: size, height: size)
    }
}

struct JournalSnippetView: View {
    var photos: [Data]
    var note: String
    var detail: String
    var body: some View {
        SiriCard {
            if !photos.isEmpty { PhotoStrip(photos: photos, height: 104) }
            if !note.isEmpty { Text(note).font(.subheadline) }
            Text(detail).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct FriendScoreSnippetView: View {
    var name: String
    var color: Color
    var streak: Int
    var best: Int
    var yourStreak: Int
    var body: some View {
        SiriCard {
            HStack(spacing: 14) {
                SiriScoreRing(value: min(100, best > 0 ? streak * 100 / best : 0), color: color, label: "\(streak)")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(String(name.prefix(1))).font(.caption.bold()).frame(width: 22, height: 22).background(color, in: .circle)
                        Text(name).font(.headline)
                    }
                    Text("\(streak)-day streak").font(.title3.weight(.bold))
                    Text("Best \(best) · you're at \(yourStreak)").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}

struct DayScoreSnippetView: View {
    var score: Int
    var label: String
    var tip: String?
    var factors: [(String, Int)]
    var body: some View {
        SiriCard {
            HStack(spacing: 14) {
                SiriScoreRing(value: score, color: Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.title3.weight(.bold))
                    if let tip { Text(tip).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(2) }
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(factors.prefix(3).enumerated()), id: \.offset) { _, f in
                    Divider().overlay(.white.opacity(0.1))
                    HStack {
                        Text(f.0).font(.subheadline)
                        Spacer()
                        Text(f.1 >= 0 ? "+\(f.1)" : "−\(-f.1)").font(.subheadline.bold())
                            .foregroundStyle(f.1 >= 0 ? Theme.accent : .orange)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
    }
}

struct WhereWasISnippetView: View {
    var name: String
    var timeText: String
    var note: String?
    var map: Data?
    var body: some View {
        SiriCard {
            HStack(spacing: 12) {
                if let map, let image = UIImage(data: map) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 66, height: 66)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.headline)
                    Text(timeText).font(.caption).foregroundStyle(.white.opacity(0.6))
                    if let note { Text(note).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
                }
            }
        }
    }
}

struct StreakSnippetView: View {
    var days: Int
    var best: Int
    var rows: [(String, Color, Int)]
    var body: some View {
        SiriCard {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(days)").font(.scaled(size: 38, weight: .bold))
                Text("days in a row · best \(best)").font(.subheadline).foregroundStyle(.white.opacity(0.6))
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    Divider().overlay(.white.opacity(0.1))
                    HStack(spacing: 10) {
                        Text(String(r.0.prefix(1))).font(.caption.bold()).frame(width: 22, height: 22).background(r.1, in: .circle)
                        Text(r.0).font(.subheadline)
                        Spacer()
                        Text("\(r.2)").font(.subheadline.bold())
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

/// Map image with the driving route drawn on it (Siri cards can't host a live map).
struct RouteSnapshot {
    var image: Data
    var etaText: String
    var detailText: String

    @MainActor
    static func make(to destination: CLLocationCoordinate2D, name: String, from start: CLLocationCoordinate2D? = nil) async -> RouteSnapshot? {
        guard let from = start ?? LocationService.shared.lastLocation?.coordinate else { return nil }
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        req.transportType = .automobile
        guard let route = try? await MKDirections(request: req).calculate().routes.first else { return nil }
        let minutes = max(1, Int((route.expectedTravelTime / 60).rounded()))
        let dist = Measurement(value: route.distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
        let options = MKMapSnapshotter.Options()
        let rect = route.polyline.boundingMapRect
        options.mapRect = rect.insetBy(dx: -rect.width * 0.25 - 400, dy: -rect.height * 0.35 - 400)
        options.size = CGSize(width: 340, height: 170)
        options.traitCollection = UITraitCollection(userInterfaceStyle: UITraitCollection.current.userInterfaceStyle)
        options.pointOfInterestFilter = .excludingAll
        guard let snap = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let img = UIGraphicsImageRenderer(size: options.size).image { ctx in
            snap.image.draw(at: .zero)
            let cg = ctx.cgContext
            let pts = UnsafeBufferPointer(start: route.polyline.points(), count: route.polyline.pointCount)
                .map { snap.point(for: $0.coordinate) }
            if let first = pts.first {
                cg.setStrokeColor(UIColor.systemBlue.cgColor); cg.setLineWidth(6); cg.setLineCap(.round); cg.setLineJoin(.round)
                cg.move(to: first); pts.dropFirst().forEach { cg.addLine(to: $0) }; cg.strokePath()
            }
            func dot(_ p: CGPoint, _ c: UIColor, _ r: CGFloat) {
                cg.setFillColor(UIColor.white.cgColor); cg.fillEllipse(in: CGRect(x: p.x - r - 3, y: p.y - r - 3, width: 2 * r + 6, height: 2 * r + 6))
                cg.setFillColor(c.cgColor); cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            }
            dot(snap.point(for: from), .systemBlue, 7)
            dot(snap.point(for: destination), .systemOrange, 10)
        }
        guard let data = img.pngData() else { return nil }
        let road = route.name.isEmpty ? "" : " · via \(route.name)"
        return RouteSnapshot(image: data, etaText: "\(minutes) min", detailText: "\(minutes) min · \(dist)\(road)")
    }

    /// Small map of a single spot (for "Where was I").
    @MainActor
    static func spot(_ c: CLLocationCoordinate2D) async -> Data? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: c, latitudinalMeters: 600, longitudinalMeters: 600)
        options.size = CGSize(width: 132, height: 132)
        options.traitCollection = UITraitCollection(userInterfaceStyle: UITraitCollection.current.userInterfaceStyle)
        guard let snap = try? await MKMapSnapshotter(options: options).start() else { return nil }
        return UIGraphicsImageRenderer(size: options.size).image { ctx in
            snap.image.draw(at: .zero)
            let p = snap.point(for: c); let cg = ctx.cgContext
            cg.setFillColor(UIColor.white.cgColor); cg.fillEllipse(in: CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26))
            cg.setFillColor(UIColor.systemBlue.cgColor); cg.fillEllipse(in: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20))
        }.pngData()
    }
}
