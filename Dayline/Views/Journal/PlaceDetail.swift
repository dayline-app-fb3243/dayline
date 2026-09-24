import SwiftUI
import MapKit

/// Phone and opening hours for a place. Demo places carry sample hours; for real places these come from
/// the saved phone number, and hours from Apple Maps' place card (MapKit doesn't hand hours to apps directly).
struct PlaceInfo {
    var phone: String?
    /// Per weekday (1 = Sunday ... 7 = Saturday): opening and closing hour, nil = closed.
    var hours: [Int: (Int, Int)?]?

    static func demo(_ name: String, phone: String?) -> PlaceInfo {
        func every(_ o: Int, _ c: Int, closed: Set<Int> = []) -> [Int: (Int, Int)?] {
            Dictionary(uniqueKeysWithValues: (1...7).map { ($0, closed.contains($0) ? nil : (o, c)) })
        }
        switch name {
        case "Ferrara Bakery": return PlaceInfo(phone: phone ?? "(212) 555-0172", hours: every(7, 19))
        case "Lucia Trattoria": return PlaceInfo(phone: phone ?? "(212) 555-0148", hours: every(12, 22, closed: [2]))
        case "Blue Door Coffee": return PlaceInfo(phone: phone ?? "(212) 555-0190", hours: every(6, 17))
        case "Iron Works Gym": return PlaceInfo(phone: phone ?? "(212) 555-0115", hours: every(5, 20))
        case "Riverside Park": return PlaceInfo(phone: nil, hours: every(6, 24))
        default: return PlaceInfo(phone: phone, hours: nil)
        }
    }

    private static func hourText(_ h: Int) -> String {
        let d = Calendar.current.date(bySettingHour: h % 24, minute: 0, second: 0, of: .now)!
        return h == 24 ? "Midnight" : d.formatted(date: .omitted, time: .shortened)
    }
    /// "Open · Closes 7 PM" / "Closed · Opens 12 PM".
    func status(now: Date = .now) -> (open: Bool, text: String)? {
        guard let hours else { return nil }
        let cal = Calendar.current
        let wd = cal.component(.weekday, from: now), h = cal.component(.hour, from: now)
        if let today = hours[wd] ?? nil, h >= today.0 && h < today.1 { return (true, "Closes \(Self.hourText(today.1))") }
        if let today = hours[wd] ?? nil, h < today.0 { return (false, "Opens \(Self.hourText(today.0))") }
        for i in 1...7 {
            let d = (wd - 1 + i) % 7 + 1
            if let next = hours[d] ?? nil {
                let name = cal.weekdaySymbols[d - 1]
                return (false, i == 1 ? "Opens \(Self.hourText(next.0)) tomorrow" : "Opens \(name) \(Self.hourText(next.0))")
            }
        }
        return (false, "Closed")
    }
    func weekRows() -> [(day: String, text: String, isToday: Bool)] {
        guard let hours else { return [] }
        let cal = Calendar.current
        let today = cal.component(.weekday, from: .now)
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 + 1 }
        return order.map { d in
            let text = (hours[d] ?? nil).map { "\(Self.hourText($0.0)) \u{2013} \(Self.hourText($0.1))" } ?? "Closed"
            return (cal.weekdaySymbols[d - 1], text, d == today)
        }
    }
}

enum PlaceLinks {
    static func directions(to c: CLLocationCoordinate2D?, name: String) {
        guard let c else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
    static func call(_ phone: String?) {
        guard let phone, let url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) else { return }
        UIApplication.shared.open(url)
    }
}

/// Walking time from here, for the Directions button ("12 min").
struct TravelTime: View {
    var to: CLLocationCoordinate2D?
    @State private var text: String?
    var body: some View {
        Text(text ?? "Directions")
            .task {
                guard let to, let from = LocationService.shared.lastLocation?.coordinate else { return }
                let r = MKDirections.Request()
                r.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
                r.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
                r.transportType = .walking
                if let eta = try? await MKDirections(request: r).calculateETA() {
                    text = "\(Int(eta.expectedTravelTime / 60)) min"
                }
            }
    }
}

/// Everything a place result can show: photos (or Look Around), when you were there, phone, hours.
struct PlaceDetailData {
    var hit: SearchHit
    var visit: Visit?
    var photos: [Data]
    var info: PlaceInfo { PlaceInfo.demo(hit.place, phone: visit?.phoneNumber) }
    var visitText: String {
        let day = hit.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let t = hit.date.formatted(date: .omitted, time: .shortened)
        if let v = visit, let d = v.departure { return "\(day) \u{00B7} \(t) \u{2013} \(d.formatted(date: .omitted, time: .shortened))" }
        return "\(day) \u{00B7} \(t)"
    }
    var note: String? {
        guard let r = hit.reason.firstIndex(of: "\u{201C}") else { return nil }
        return String(hit.reason[r...]).trimmingCharacters(in: CharacterSet(charactersIn: "\u{201C}\u{201D}"))
    }
}

struct PlacePhotoStrip: View {
    var data: PlaceDetailData
    var height: CGFloat = 130
    @State private var scene: MKLookAroundScene?
    var body: some View {
        Group {
            if !data.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(data.photos.enumerated()), id: \.offset) { _, d in
                            if let img = UIImage(data: d) {
                                Image(uiImage: img).resizable().scaledToFill().frame(width: data.photos.count == 1 ? 300 : 150, height: height).clipShape(.rect(cornerRadius: 14))
                            }
                        }
                    }
                }
            } else if let scene {
                LookAroundPreview(initialScene: scene, allowsNavigation: false, showsRoadLabels: false)
                    .frame(height: height).clipShape(.rect(cornerRadius: 14))
            }
        }
        .task {
            guard data.photos.isEmpty, let c = data.hit.coordinate else { return }
            scene = try? await MKLookAroundSceneRequest(coordinate: c).scene
        }
    }
}

/// Three equal action buttons, like Apple Maps: Directions (blue), Call, Hours.
struct PlaceActionButtons: View {
    var data: PlaceDetailData
    var glass = false
    @Binding var showHours: Bool
    var body: some View {
        HStack(spacing: 8) {
            action(symbol: "figure.walk", title: AnyView(TravelTime(to: data.hit.coordinate)), primary: true) {
                PlaceLinks.directions(to: data.hit.coordinate, name: data.hit.place)
            }
            .accessibilityIdentifier("placeDirections")
            if data.info.phone != nil {
                action(symbol: "phone.fill", title: AnyView(Text("Call")), primary: false) { PlaceLinks.call(data.info.phone) }
            }
            if data.info.hours != nil {
                action(symbol: "clock.fill", title: AnyView(Text("Hours")), primary: false) { withAnimation(.snappy) { showHours.toggle() } }
            }
        }
    }
    @ViewBuilder private func action(symbol: String, title: AnyView, primary: Bool, run: @escaping () -> Void) -> some View {
        let label = VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
            title.font(.caption.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity).frame(height: 60)
        .foregroundStyle(primary ? .white : Theme.accent)
        if primary {
            Button(action: run) { label }.buttonStyle(.plain).background(Theme.accent, in: .rect(cornerRadius: 16))
        } else if glass {
            Button(action: run) { label }.buttonStyle(.plain).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        } else {
            Button(action: run) { label }.buttonStyle(.plain).background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 16))
        }
    }
}

struct HoursStatusLine: View {
    var info: PlaceInfo
    var body: some View {
        if let s = info.status() {
            (Text(s.open ? "Open" : "Closed").foregroundStyle(s.open ? Color.green : Color.red).fontWeight(.semibold)
             + Text(" \u{00B7} \(s.text)").foregroundStyle(.secondary))
                .font(.subheadline)
        }
    }
}

struct WeekHours: View {
    var info: PlaceInfo
    var body: some View {
        VStack(spacing: 6) {
            ForEach(info.weekRows(), id: \.day) { r in
                HStack {
                    Text(r.day).fontWeight(r.isToday ? .semibold : .regular)
                    Spacer()
                    Text(r.text).foregroundStyle(r.isToday ? .primary : .secondary).fontWeight(r.isToday ? .semibold : .regular)
                }
                .font(.subheadline)
            }
        }
    }
}

/// One confident result. Preview flag "search.one" (none picked yet):
/// A = compact card, three action buttons, hours open/closed line (tap Hours for the week).
/// B = photo on top with the name over it, glass buttons, hours list always showing.
/// C = Apple Maps place sheet: map, big Directions button, info rows (Hours, Phone, Your visit).
struct SinglePlaceResult: View {
    var data: PlaceDetailData
    var style: String
    @State private var showHours = false

    var body: some View {
        switch style {
        case "B": styleB
        case "C": styleC
        default: styleA
        }
    }

    private var styleA: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Map inset with a white margin, not edge to edge.
            MiniPlaceMap(coordinate: data.hit.coordinate, symbol: data.hit.symbol, distance: 900).frame(height: 130)
                .clipShape(.rect(cornerRadius: 16)).padding([.horizontal, .top], 10)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(data.hit.place).font(.title2.weight(.bold))
                    HoursStatusLine(info: data.info)
                    Text("You were here \(data.visitText)").font(.subheadline).foregroundStyle(.secondary)
                }
                PlacePhotoStrip(data: data, height: 110)
                PlaceActionButtons(data: data, showHours: $showHours)
                if showHours { WeekHours(info: data.info).padding(.top, 2) }
            }
            .padding(16)
        }
        .background(Color(.systemBackground).opacity(0.9))
        .clipShape(.rect(cornerRadius: 24))
        .accessibilityIdentifier("searchHit")
    }

    private var styleB: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let d = data.photos.first, let img = UIImage(data: d) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        MiniPlaceMap(coordinate: data.hit.coordinate, symbol: data.hit.symbol, distance: 700)
                    }
                }
                .frame(height: 220).frame(maxWidth: .infinity).clipped()
                LinearGradient(stops: [.init(color: .black.opacity(0), location: 0.4), .init(color: .black.opacity(0.7), location: 1)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.hit.place).font(.system(size: 28, weight: .heavy)).foregroundStyle(.white)
                    Text(data.visitText).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                }
                .padding(16)
            }
            .frame(height: 220)
            .clipShape(.rect(cornerRadius: 24))
            PlaceActionButtons(data: data, glass: true, showHours: $showHours)
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Hours").font(.headline); Spacer(); HoursStatusLine(info: data.info) }
                WeekHours(info: data.info)
            }
            .padding(16)
            .background(Color(.systemBackground).opacity(0.85), in: .rect(cornerRadius: 20))
        }
        .accessibilityIdentifier("searchHit")
    }

    private var styleC: some View {
        VStack(alignment: .leading, spacing: 0) {
            MiniPlaceMap(coordinate: data.hit.coordinate, symbol: data.hit.symbol, distance: 1100).frame(height: 180)
                .clipShape(.rect(cornerRadius: 18)).padding([.horizontal, .top], 10)
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.hit.place).font(.title.weight(.bold))
                    Text(data.hit.symbol == "fork.knife" ? "Restaurant" : data.hit.symbol == "cup.and.saucer.fill" ? "Bakery & Caf\u{00E9}" : "Place")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button { PlaceLinks.directions(to: data.hit.coordinate, name: data.hit.place) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.walk")
                        Text("Directions")
                        Text("\u{00B7}").opacity(0.7)
                        TravelTime(to: data.hit.coordinate).opacity(0.9)
                    }
                    .font(.headline).frame(maxWidth: .infinity).frame(height: 52)
                }
                .buttonStyle(.plain).foregroundStyle(.white).background(Theme.accent, in: .capsule)
                .accessibilityIdentifier("placeDirections")
                PlacePhotoStrip(data: data, height: 100)
                VStack(spacing: 0) {
                    Button { withAnimation(.snappy) { showHours.toggle() } } label: {
                        infoRow("clock", "Hours") { HoursStatusLine(info: data.info) }
                    }.buttonStyle(.plain)
                    if showHours { WeekHours(info: data.info).padding(.horizontal, 16).padding(.bottom, 10) }
                    Divider().padding(.leading, 48)
                    if let phone = data.info.phone {
                        Button { PlaceLinks.call(phone) } label: {
                            infoRow("phone", "Phone") { Text(phone).font(.subheadline).foregroundStyle(Theme.accent) }
                        }.buttonStyle(.plain)
                        Divider().padding(.leading, 48)
                    }
                    Button { MapJump.go(data.hit) } label: {
                        infoRow("mappin.and.ellipse", "Your visit") { Text(data.visitText).font(.subheadline).foregroundStyle(.secondary) }
                    }.buttonStyle(.plain)
                }
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
            }
            .padding(16)
        }
        .background(Color(.systemBackground).opacity(0.95))
        .clipShape(.rect(cornerRadius: 24))
        .accessibilityIdentifier("searchHit")
    }

    private func infoRow<V: View>(_ symbol: String, _ title: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                value()
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(.rect)
    }
}

/// After tapping a place on "Which one did you mean?". Preview flag "search.detail" (none picked yet):
/// A = a sheet slides up over the list. B = its own full screen with a big map. C = the row opens in place.
struct PlaceDetailScreen: View {
    var data: PlaceDetailData
    @Environment(\.dismiss) private var dismiss
    @State private var showHours = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MiniPlaceMap(coordinate: data.hit.coordinate, symbol: data.hit.symbol, distance: 900)
                    .frame(height: 300).clipShape(.rect(cornerRadius: 28))
                VStack(alignment: .leading, spacing: 4) {
                    Text(data.hit.place).font(.largeTitle.weight(.bold))
                    HoursStatusLine(info: data.info)
                    Text("You were here \(data.visitText)").font(.subheadline).foregroundStyle(.secondary)
                }
                PlaceActionButtons(data: data, glass: true, showHours: $showHours)
                if showHours { WeekHours(info: data.info) }
                PlacePhotoStrip(data: data, height: 140)
                if let note = data.note {
                    Text("\u{201C}\(note)\u{201D}").font(.body).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground).opacity(0.85), in: .rect(cornerRadius: 16))
                }
                Button { MapJump.go(data.hit) } label: {
                    Label("Show on Timeline", systemImage: "map").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent).glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(16)
        }
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PlaceDetailSheet: View {
    var data: PlaceDetailData
    @State private var showHours = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(data.hit.place).font(.title2.weight(.bold))
                    HoursStatusLine(info: data.info)
                    Text("You were here \(data.visitText)").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            PlaceActionButtons(data: data, glass: true, showHours: $showHours)
            if showHours { WeekHours(info: data.info) }
            PlacePhotoStrip(data: data, height: 120)
            if let note = data.note { Text("\u{201C}\(note)\u{201D}").font(.subheadline).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 24)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
