import SwiftUI
import MapKit

/// Binding helper: a time stored as minutes after midnight, shown with Apple's time picker.
private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
    Binding(get: { UserSchedule.date(minutes.wrappedValue, on: .now) },
            set: { minutes.wrappedValue = UserSchedule.minutes(of: $0) })
}

/// Profile > Your Schedule: wake, bed, work hours per day, and habit switches.
struct YourScheduleView: View {
    @State private var s = UserSchedule.current
    @State private var editing: WorkBlock?
    @State private var adding = false
    @State private var pickingWork = false
    @State private var pickingGym = false
    private func savePlace(_ item: MKMapItem, kind: String) {
        s.places.removeAll { $0.kind == kind }
        s.places.append(SavedPlace(kind: kind, name: item.name ?? (kind == "work" ? "Work" : "Gym"),
                                   address: AddPlaceView.address(item), latitude: item.location.coordinate.latitude,
                                   longitude: item.location.coordinate.longitude))
    }

    var body: some View {
        Form {
            Section("Sleep") {
                HStack {
                    Text("Wake Up")
                    Spacer()
                    DatePicker("Wake Up", selection: timeBinding($s.wake), displayedComponents: .hourAndMinute)
                        .labelsHidden().accessibilityIdentifier("wakePicker")
                }
                .frame(minHeight: 44).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                HStack {
                    Text("Bedtime")
                    Spacer()
                    DatePicker("Bedtime", selection: timeBinding($s.bed), displayedComponents: .hourAndMinute)
                        .labelsHidden().accessibilityIdentifier("bedPicker")
                }
                .frame(minHeight: 44).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            Section {
                Toggle("I Work", isOn: $s.works.animation()).accessibilityIdentifier("worksToggle")
                if s.works {
                    Button { pickingWork = true } label: {
                        LabeledContent("Work Location") {
                            Text(s.workPlace?.name ?? "Choose")
                                .foregroundStyle(s.workPlace == nil ? Theme.accent : .secondary)
                        }
                    }
                    .tint(.primary).accessibilityIdentifier("workLocation")
                }
                if s.works {
                    ForEach(s.workBlocks) { b in
                        Button { editing = b } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.daysText).foregroundStyle(.primary)
                                    Text(b.hoursText).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("workBlock-\(b.daysText)")
                    }
                    .onDelete { s.workBlocks.remove(atOffsets: $0) }
                    Button("Add Work Hours") { adding = true }.accessibilityIdentifier("addWorkHours")
                }
            } header: { Text("Work") } footer: {
                if s.works { Text("Set different hours for different days. Days with no hours are days off.") }
            }
            Section {
                Toggle("Gym", isOn: $s.gym)
                if s.gym {
                    Button { pickingGym = true } label: {
                        LabeledContent("Gym Location") {
                            Text(s.gymPlace?.name ?? "Choose")
                                .foregroundStyle(s.gymPlace == nil ? Theme.accent : .secondary)
                        }
                    }
                    .tint(.primary).accessibilityIdentifier("gymLocation")
                    if let gym = s.gymPlace,
                       let c = GymHours.cached, !c.sample, c.name == gym.name,
                       let close = GymHours.closing(on: .now) {
                        LabeledContent("Closes") {
                            Text(UserSchedule.date(close, on: .now).formatted(date: .omitted, time: .shortened))
                        }.accessibilityIdentifier("gymBy")
                    }
                }
                Toggle(isOn: $s.walk) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Walk")
                        Text("Step goal: \(s.stepGoal.formatted()) \u{00B7} based on your usual day").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Toggle("Journal", isOn: $s.journal)
            } header: { Text("My Habits") } footer: {
                Text("Your day score only counts what\u{2019}s on. Points are shared between them, so a full day of your own routine is 100. A habit only counts as missed once its time is up.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackgroundView())
        .navigationTitle("Your Schedule")
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickingWork) {
            NavigationStack {
                AddPlaceView(title: "Work Location", prompt: "Search for work") { item in
                    savePlace(item, kind: "work")
                }
            }
        }
        .sheet(isPresented: $pickingGym) {
            NavigationStack {
                AddPlaceView(title: "Gym Location", prompt: "Search for your gym", categories: [.fitnessCenter]) { item in
                    savePlace(item, kind: "gym")
                }
            }
        }
        .onChange(of: s) { old, new in
            UserSchedule.current = new
            if old.bed != new.bed { Task { await Notifications.refreshJournalReminderIfNeeded() } }
        }
        .onAppear { s = UserSchedule.current }
        .sheet(item: $editing) { b in
            NavigationStack {
                WorkHoursView(block: b, taken: takenDays(except: b.id), onSave: { nb in
                    if let i = s.workBlocks.firstIndex(where: { $0.id == nb.id }) { s.workBlocks[i] = nb }
                }, onDelete: { s.workBlocks.removeAll { $0.id == b.id } })
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                WorkHoursView(block: WorkBlock(days: []), taken: takenDays(except: nil), isNew: true,
                              onSave: { s.workBlocks.append($0) }, onDelete: nil)
            }
        }
    }

    private func takenDays(except id: UUID?) -> Set<Int> {
        Set(s.workBlocks.filter { $0.id != id }.flatMap(\.days))
    }
}

/// Edit one set of work hours: which days, start and end. Like Apple's Sleep / Focus schedules.
struct WorkHoursView: View {
    @State var block: WorkBlock
    var taken: Set<Int>
    var isNew = false
    var onSave: (WorkBlock) -> Void
    var onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    private let order = [1, 2, 3, 4, 5, 6, 7]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 0) {
                    ForEach(order, id: \.self) { d in
                        let on = block.days.contains(d), busy = taken.contains(d)
                        Button {
                            if on { block.days.remove(d) } else if !busy { block.days.insert(d) }
                        } label: {
                            Text(String(Calendar.current.veryShortWeekdaySymbols[d - 1]))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(on ? .white : busy ? Color(.tertiaryLabel) : .primary)
                                .frame(width: 38, height: 38)
                                .background(on ? Theme.accent : Color(.tertiarySystemFill), in: .circle)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("day-\(d)")
                    }
                }
                .padding(.vertical, 4)
            } header: { Text("Days") } footer: {
                Text(block.days.isEmpty ? "Pick the days these hours are for." : "Every \(block.daysText == "Weekdays" ? "weekday" : block.daysText)")
            }
            Section("Hours") {
                DatePicker("Starts", selection: timeBinding($block.start), displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: timeBinding($block.end), displayedComponents: .hourAndMinute)
            }
            if let onDelete {
                Section {
                    Button("Delete Work Hours", role: .destructive) { onDelete(); dismiss() }.frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Work Hours")
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onSave(block); dismiss() }.disabled(block.days.isEmpty).accessibilityIdentifier("workHoursDone")
            }
        }
    }
}

// MARK: - Places

/// Profile > Places: Home, Work and your own places, found with Apple Maps search.
struct PlacesView: View {
    @AppStorage("symbols.show") private var showSymbols = true
    @State private var s = UserSchedule.current
    @State private var adding: String?

    var body: some View {
        Form {
            Section {
                row(kind: "home", title: "Home", symbol: "house.fill", color: .blue, place: s.home)
                row(kind: "work", title: "Work", symbol: "briefcase.fill", color: .brown, place: s.workPlace)
                row(kind: "gym", title: "Gym", symbol: "dumbbell.fill", color: .green, place: s.gymPlace)
            } footer: { Text("Dayline uses these to know when you\u{2019}re home, at work, and at your gym. If you go to the same gym on 10 days, Dayline adds it here for you.") }
            Section("My Places") {
                ForEach(s.places.filter { $0.kind == "other" }) { p in
                    HStack(spacing: 12) {
                        if showSymbols {
                            Image(systemName: "mappin").font(.footnote.weight(.bold)).foregroundStyle(.white)
                                .markerBackground(Color.red, size: 30)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                            Text(p.address).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .onDelete { idx in
                    let others = s.places.filter { $0.kind == "other" }
                    let ids = Set(idx.map { others[$0].id })
                    s.places.removeAll { ids.contains($0.id) }
                }
                Button("Add Place") { adding = "other" }.accessibilityIdentifier("addPlace")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackgroundView())
        .navigationTitle("Places")
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: s) { _, new in UserSchedule.current = new }
        .onAppear { s = UserSchedule.current }
        .sheet(item: Binding(get: { adding.map { KindBox(kind: $0) } }, set: { adding = $0?.kind })) { box in
            NavigationStack {
                AddPlaceView(title: box.kind == "home" ? "Home" : box.kind == "work" ? "Work" : box.kind == "gym" ? "Gym" : "Add Place",
                             categories: box.kind == "gym" ? [.fitnessCenter] : nil) { item in
                    let place = SavedPlace(kind: box.kind, name: box.kind == "home" ? "Home" : box.kind == "work" ? "Work" : (item.name ?? (box.kind == "gym" ? "Gym" : "Place")),
                                           address: AddPlaceView.address(item), latitude: item.location.coordinate.latitude,
                                           longitude: item.location.coordinate.longitude)
                    if box.kind != "other" { s.places.removeAll { $0.kind == box.kind } }
                    s.places.append(place)
                }
            }
        }
    }

    private struct KindBox: Identifiable { var kind: String; var id: String { kind } }

    private func row(kind: String, title: String, symbol: String, color: Color, place: SavedPlace?) -> some View {
        Button { adding = kind } label: {
            HStack(spacing: 12) {
                if showSymbols {
                    Image(systemName: symbol).font(.footnote.weight(.bold)).foregroundStyle(.white)
                        .markerBackground(color, size: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(place?.address ?? "Add Address").font(.subheadline).foregroundStyle(place == nil ? Theme.accent : .secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("place-\(kind)")
    }
}

/// Apple Maps search (MapKit, same data as Apple Maps) with Maps-style result rows.
@MainActor
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }
    func update(_ q: String) { if q.isEmpty { results = [] } else { completer.queryFragment = q } }
    nonisolated func completerDidUpdateResults(_ c: MKLocalSearchCompleter) {
        let r = c.results
        Task { @MainActor in self.results = r }
    }
    nonisolated func completer(_ c: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

/// Apple Maps place search limited to one kind of place (for example gyms): real businesses with their
/// addresses, ranked near you, the way Apple Maps lists them. Streets and addresses are left out.
@MainActor
final class PlaceKindSearch: ObservableObject {
    @Published var items: [MKMapItem] = []
    @Published var loading = false
    @Published var searchFailed = false
    var categories: [MKPointOfInterestCategory]
    private var task: Task<Void, Never>?
    init(categories: [MKPointOfInterestCategory]) { self.categories = categories }
    /// Search the person's live location when available. Never imply a saved or demo city is nearby.
    static var nearCenter: CLLocationCoordinate2D? {
        guard let fix = LocationService.shared.lastLocation, fix.horizontalAccuracy >= 0,
              abs(fix.timestamp.timeIntervalSinceNow) < 15 * 60 else { return nil }
        return fix.coordinate
    }
    func search(_ q: String, categories: [MKPointOfInterestCategory]) { self.categories = categories; update(q) }
    func update(_ q: String) {
        task?.cancel()
        let term = q.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty query means "gyms nearby" when location is known.
        guard !term.isEmpty || Self.nearCenter != nil else { items = []; loading = false; return }
        loading = true; searchFailed = false
        task = Task {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            let r = MKLocalSearch.Request()
            r.naturalLanguageQuery = term.isEmpty ? "gym" : term
            r.resultTypes = .pointOfInterest
            r.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
            if let c = Self.nearCenter { r.region = MKCoordinateRegion(center: c, latitudinalMeters: 12_000, longitudinalMeters: 12_000) }
            let response = try? await MKLocalSearch(request: r).start()
            if Task.isCancelled { return }
            let found = response?.mapItems ?? []
            searchFailed = response == nil
            loading = false
            if let c = Self.nearCenter {
                let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
                items = found.sorted { $0.location.distance(from: here) < $1.location.distance(from: here) }
            } else { items = found }
        }
    }
    func distanceText(_ item: MKMapItem) -> String? {
        guard let c = Self.nearCenter else { return nil }
        let m = item.location.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
        return Measurement(value: m, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

struct AddPlaceView: View {
    @AppStorage("symbols.show") private var showSymbols = true
    var title: String
    var prompt = "Search Maps"
    var dismissOnPick = true
    /// Only these kinds of places (gyms: [.fitnessCenter]). nil = any place or address.
    var categories: [MKPointOfInterestCategory]? = nil
    var onPick: (MKMapItem) -> Void
    @StateObject private var search = PlaceSearch()
    @StateObject private var kindSearch = PlaceKindSearch(categories: [])
    @State private var query = ""
    @State private var searchAllPlaces = false
    @ObservedObject private var location = LocationService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let cats = categories, !searchAllPlaces {
                if query.isEmpty && PlaceKindSearch.nearCenter == nil {
                    Text("Allow location in Settings to see nearby gyms. You can still search by name.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section(query.isEmpty ? "Gyms nearby" : "Gym results") {
                if kindSearch.loading { ProgressView("Searching Apple Maps…") }
                if !kindSearch.loading && kindSearch.items.isEmpty && PlaceKindSearch.nearCenter != nil {
                    Text(kindSearch.searchFailed ? "Apple Maps could not load gyms. Search by name or try again." : "No gyms found nearby. Search by name or address.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(kindSearch.items, id: \.self) { item in
                    Button { onPick(item); if dismissOnPick { dismiss() } } label: {
                        HStack(spacing: 12) {
                            let g = kindGlyph(cats)
                            if showSymbols {
                                Image(systemName: g.0).font(.footnote.weight(.bold)).foregroundStyle(.white)
                                    .frame(width: 32, height: 32).background(g.1, in: .circle)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "").foregroundStyle(.primary)
                                let sub = [kindSearch.distanceText(item), Self.address(item)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
                                if !sub.isEmpty { Text(sub).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("placeResult")
                }
                }
                Button("Search all places or enter an address") {
                    searchAllPlaces = true
                    if !query.isEmpty { search.update(query) }
                }
                .accessibilityIdentifier("searchAllPlaces")
            } else {
            ForEach(search.results, id: \.self) { r in
                Button { pick(r) } label: {
                    HStack(spacing: 12) {
                        let g = glyph(r)
                        if showSymbols {
                            Image(systemName: g.0).font(.footnote.weight(.bold)).foregroundStyle(.white)
                                .frame(width: 32, height: 32).background(g.1, in: .circle)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).foregroundStyle(.primary)
                            if !r.subtitle.isEmpty { Text(r.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("placeResult")
            }
                if categories != nil && searchAllPlaces {
                    Button("Search gyms nearby") { searchAllPlaces = false; kindSearch.update(query) }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        .onChange(of: query) { _, q in
            if let cats = categories, !searchAllPlaces { kindSearch.search(q, categories: cats) } else { search.update(q) }
        }
        .onChange(of: location.lastSample) {
            if let cats = categories, query.isEmpty && !searchAllPlaces { kindSearch.search("", categories: cats) }
        }
        .task { if let cats = categories { kindSearch.search("", categories: cats) } }
        .navigationTitle(title)
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } } }
    }

    private func kindGlyph(_ cats: [MKPointOfInterestCategory]) -> (String, Color) {
        if cats.contains(.fitnessCenter) { return ("dumbbell.fill", .purple) }
        if cats.contains(.university) || cats.contains(.school) { return ("graduationcap.fill", .brown) }
        return ("mappin", .red)
    }

    /// Maps-style glyphs: red pin for addresses, gray building, orange cup for coffee, and so on.
    private func glyph(_ r: MKLocalSearchCompletion) -> (String, Color) {
        let t = (r.title + " " + r.subtitle).lowercased()
        if t.contains("coffee") || t.contains("caf") { return ("cup.and.saucer.fill", .orange) }
        if t.contains("gym") || t.contains("fitness") { return ("dumbbell.fill", .purple) }
        if t.contains("restaurant") || t.contains("pizza") || t.contains("grill") { return ("fork.knife", .orange) }
        if t.contains("park") { return ("tree.fill", .green) }
        if r.subtitle.isEmpty || r.title.first?.isNumber == true { return ("mappin", .red) }
        return ("building.2.fill", .gray)
    }

    private func pick(_ r: MKLocalSearchCompletion) {
        Task {
            if let item = try? await MKLocalSearch(request: .init(completion: r)).start().mapItems.first {
                onPick(item); if dismissOnPick { dismiss() }
            }
        }
    }

    static func address(_ item: MKMapItem) -> String {
        if let a = item.address?.shortAddress ?? item.address?.fullAddress { return a }
        return item.name ?? ""
    }
}


extension UserSchedule {
    mutating func setGym(_ item: MKMapItem) {
        places.removeAll { $0.kind == "gym" }
        places.append(SavedPlace(kind: "gym", name: item.name ?? "Gym", address: AddPlaceView.address(item),
                                 latitude: item.location.coordinate.latitude, longitude: item.location.coordinate.longitude))
    }
}

/// Turning the Gym habit on (preview "gym.ask"): only asks where your gym is. Closing hours come from
/// Google for that gym (when there's a key), so there's no time question.
/// A: the Apple Maps search, done on pick. C: the search, then a card with the gym and its closing time.
struct GymAskSheet: View {
    var style: String
    @Binding var s: UserSchedule
    @Environment(\.dismiss) private var dismiss
    @State private var picked = false

    var body: some View {
        NavigationStack {
            AddPlaceView(title: "Where\u{2019}s Your Gym?", prompt: "Search for your gym", dismissOnPick: false, categories: [.fitnessCenter]) { item in
                s.setGym(item)
                if style == "C" { picked = true } else { dismiss() }
            }
            .navigationDestination(isPresented: $picked) { confirm }
        }
    }

    private var confirm: some View {
        VStack(spacing: 16) {
            Image(systemName: "dumbbell.fill").font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 76, height: 76).background(Theme.accent.opacity(0.14), in: .circle).padding(.top, 28)
            Text(s.gymPlace?.name ?? "Your Gym").font(.title2.bold()).multilineTextAlignment(.center)
            if let a = s.gymPlace?.address, !a.isEmpty { Text(a).font(.subheadline).foregroundStyle(.secondary) }
            if let c = GymHours.cached, let close = GymHours.closing(on: .now) {
                Label("Closes \(UserSchedule.date(close, on: .now).formatted(date: .omitted, time: .shortened)) today\(c.sample ? " · sample hours" : "")",
                      systemImage: "clock").font(.body).foregroundStyle(.secondary)
            }
            Text("If you haven\u{2019}t gone by closing time, Dayline counts the gym as missed for today.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 28)
            Spacer()
            Button { dismiss() } label: { Text("Done").font(.headline).frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(.large).padding(.horizontal, 20).padding(.bottom, 12)
                .accessibilityIdentifier("gymAskDone")
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
