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

    var body: some View {
        Form {
            Section("Sleep") {
                DatePicker("Wake Up", selection: timeBinding($s.wake), displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("wakePicker")
                DatePicker("Bedtime", selection: timeBinding($s.bed), displayedComponents: .hourAndMinute)
            }
            Section {
                Toggle("I Work", isOn: $s.works.animation()).accessibilityIdentifier("worksToggle")
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
                    // The day score only counts the gym as missed after this time (e.g. when your gym closes).
                    DatePicker("Go By", selection: Binding(
                        get: { UserSchedule.date(s.gymDeadline, on: .now) },
                        set: { s.gymBy = UserSchedule.minutes(of: $0) }), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("gymBy")
                }
                Toggle(isOn: $s.walk) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Walk")
                        Text("Step goal: \(s.stepGoal.formatted()) \u{00B7} based on your usual day").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Toggle("Time Outside", isOn: $s.outside)
                Toggle("Get Out of the House", isOn: $s.getOut)
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
        .onChange(of: s) { _, new in UserSchedule.current = new }
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
    @State private var s = UserSchedule.current
    @State private var adding: String?

    var body: some View {
        Form {
            Section {
                row(kind: "home", title: "Home", symbol: "house.fill", color: .blue, place: s.home)
                row(kind: "work", title: "Work", symbol: "briefcase.fill", color: .brown, place: s.workPlace)
            } footer: { Text("Dayline uses these to know when you\u{2019}re home and when you\u{2019}re at work.") }
            Section("My Places") {
                ForEach(s.places.filter { $0.kind == "other" }) { p in
                    HStack(spacing: 12) {
                        Image(systemName: "mappin").font(.footnote.weight(.bold)).foregroundStyle(.white)
                            .markerBackground(Color.red, size: 30)
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
                AddPlaceView(title: box.kind == "home" ? "Home" : box.kind == "work" ? "Work" : "Add Place") { item in
                    let place = SavedPlace(kind: box.kind, name: box.kind == "home" ? "Home" : box.kind == "work" ? "Work" : (item.name ?? "Place"),
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
                Image(systemName: symbol).font(.footnote.weight(.bold)).foregroundStyle(.white)
                    .markerBackground(color, size: 30)
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

struct AddPlaceView: View {
    var title: String
    var onPick: (MKMapItem) -> Void
    @StateObject private var search = PlaceSearch()
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(search.results, id: \.self) { r in
                Button { pick(r) } label: {
                    HStack(spacing: 12) {
                        let g = glyph(r)
                        Image(systemName: g.0).font(.footnote.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 32, height: 32).background(g.1, in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).foregroundStyle(.primary)
                            if !r.subtitle.isEmpty { Text(r.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Maps")
        .onChange(of: query) { _, q in search.update(q) }
        .navigationTitle(title)
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } } }
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
                onPick(item); dismiss()
            }
        }
    }

    static func address(_ item: MKMapItem) -> String {
        if let a = item.address?.shortAddress ?? item.address?.fullAddress { return a }
        return item.name ?? ""
    }
}
