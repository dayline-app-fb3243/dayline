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
    /// Preview "gym.ask": what happens when you turn the Gym habit on. A = a sheet that asks where your gym is,
    /// then when it closes. B = both questions right in the list. C = one sheet with both.
    /// "" = the old plain Go By picker.
    @AppStorage("gym.ask") private var ask = ""
    @State private var askingGym = false
    @State private var pickingGym = false

    private var closesText: String? {
        guard let c = GymHours.cached, let close = GymHours.closing(on: .now) else { return nil }
        return "\(c.name) closes \(UserSchedule.date(close, on: .now).formatted(date: .omitted, time: .shortened))\(c.sample ? " · sample hours" : "")"
    }
    private func setGym(_ item: MKMapItem) { s.setGym(item) }

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
                if s.gym && ask == "B" {
                    Button { pickingGym = true } label: {
                        LabeledContent("Gym Location") {
                            Text(s.gymPlace?.name ?? "Choose").foregroundStyle(s.gymPlace == nil ? Theme.accent : .secondary)
                        }
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("gymLocation")
                    DatePicker(selection: Binding(get: { UserSchedule.date(s.gymDeadline, on: .now) },
                                                  set: { s.gymBy = UserSchedule.minutes(of: $0) }), displayedComponents: .hourAndMinute) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gym Closes")
                            Text(closesText ?? "The gym counts as missed after this").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("gymBy")
                } else if s.gym && (ask == "A" || ask == "C") {
                    Button { askingGym = true } label: {
                        LabeledContent("Gym Location") {
                            Text(s.gymPlace?.name ?? "Choose").foregroundStyle(s.gymPlace == nil ? Theme.accent : .secondary)
                        }
                    }
                    .tint(.primary)
                    DatePicker(selection: Binding(get: { UserSchedule.date(s.gymDeadline, on: .now) },
                                                  set: { s.gymBy = UserSchedule.minutes(of: $0) }), displayedComponents: .hourAndMinute) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gym Closes")
                            Text(closesText ?? "The gym counts as missed after this").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("gymBy")
                } else if s.gym, GymHours.enabled, let c = GymHours.cached, let close = GymHours.closing(on: .now) {
                    // Preview "gym.hours": the real closing time replaces the picker.
                    LabeledContent("Go By") {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(UserSchedule.date(close, on: .now).formatted(date: .omitted, time: .shortened))
                            Text("\(c.name) closes\(c.sample ? " · sample hours" : "")").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("gymBy")
                } else if s.gym {
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
        .onChange(of: s.gym) { _, on in
            if on && s.gymPlace == nil && (ask == "A" || ask == "C") { askingGym = true }
        }
        .sheet(isPresented: $askingGym) {
            GymAskSheet(style: ask, s: $s).presentationDetents(ask == "C" ? [.large] : [.large])
        }
        .sheet(isPresented: $pickingGym) {
            NavigationStack {
                AddPlaceView(title: "Your Gym", prompt: "Search for your gym") { item in setGym(item) }
            }
        }
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
                row(kind: "gym", title: "Gym", symbol: "dumbbell.fill", color: .green, place: s.gymPlace)
            } footer: { Text("Dayline uses these to know when you\u{2019}re home, at work, and at your gym. If you go to the same gym on 10 days, Dayline adds it here for you.") }
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
                AddPlaceView(title: box.kind == "home" ? "Home" : box.kind == "work" ? "Work" : box.kind == "gym" ? "Gym" : "Add Place") { item in
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
    var prompt = "Search Maps"
    var dismissOnPick = true
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
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
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

/// Turning the Gym habit on (preview "gym.ask"). A: step 1 finds your gym on Apple Maps, step 2 asks when
/// it closes. C: one page with both questions.
struct GymAskSheet: View {
    var style: String
    @Binding var s: UserSchedule
    @Environment(\.dismiss) private var dismiss
    @State private var step2 = false
    @State private var picking = false

    private var latest: Binding<Date> {
        Binding(get: { UserSchedule.date(s.gymDeadline, on: .now) }, set: { s.gymBy = UserSchedule.minutes(of: $0) })
    }

    var body: some View {
        NavigationStack {
            if style == "C" { onePage } else {
                AddPlaceView(title: "Where\u{2019}s Your Gym?", prompt: "Search for your gym", dismissOnPick: false) { item in
                    s.setGym(item); step2 = true
                }
                .navigationDestination(isPresented: $step2) { latestPage }
            }
        }
    }

    private var latestPage: some View {
        VStack(spacing: 18) {
            Image(systemName: "dumbbell.fill").font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 76, height: 76).background(Theme.accent.opacity(0.14), in: .circle).padding(.top, 24)
            Text("When does your gym close?").font(.title2.bold()).multilineTextAlignment(.center)
            Text("If you haven\u{2019}t gone by closing time, Dayline counts the gym as missed for today.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
            DatePicker("Gym Closes", selection: latest, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel).labelsHidden()
            if let g = s.gymPlace { Label(g.name, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary) }
            Spacer()
            Button { dismiss() } label: { Text("Done").font(.headline).frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(.large).padding(.horizontal, 20).padding(.bottom, 12)
                .accessibilityIdentifier("gymAskDone")
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var onePage: some View {
        Form {
            Section {
                Button { picking = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dumbbell.fill").font(.footnote.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 32, height: 32).background(Color.purple, in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.gymPlace?.name ?? "Choose Your Gym").foregroundStyle(s.gymPlace == nil ? Theme.accent : .primary)
                            if let a = s.gymPlace?.address, !a.isEmpty { Text(a).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                }
                .accessibilityIdentifier("gymChoose")
            } header: { Text("Where\u{2019}s your gym?") }
            Section {
                DatePicker("Gym Closes", selection: latest, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
            } header: { Text("When does it close?") } footer: {
                Text("If you haven\u{2019}t gone by closing time, Dayline counts the gym as missed for today.")
            }
        }
        .navigationTitle("Gym")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("gymAskDone") }
        }
        .sheet(isPresented: $picking) {
            NavigationStack { AddPlaceView(title: "Your Gym", prompt: "Search for your gym") { item in s.setGym(item) } }
        }
    }
}
