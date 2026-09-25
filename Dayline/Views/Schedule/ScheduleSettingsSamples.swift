import SwiftUI
import MapKit

/// Profile > Your Schedule, picking between layouts. "settings.layout" "" = today's screen; 1-8 = sample layouts
/// for the redesign: Places (Home first, a place only for habits that are on), Times, and Habits
/// (Gym, Run, Walk, Journal, Work, School and a few more). Sample-only until one is picked.
struct YourScheduleEntry: View {
    @AppStorage("settings.layout") private var layout = ""
    var body: some View {
        if layout.isEmpty { YourScheduleView() } else { ScheduleSettingsSamples(style: layout) }
    }
}

struct ScheduleSettingsSamples: View {
    var style: String
    /// "settings.fresh": start sample 1 as a new user would (Gym and School off, no gym or school set) to show each step.
    private static let fresh = UserDefaults.standard.bool(forKey: "settings.fresh")
    @State private var gym = !Self.fresh
    @State private var gymPlace: String? = Self.fresh ? nil : "Iron Works Gym"
    @State private var workPlace: String? = "Park Ave S"
    @State private var schoolPlace: String? = nil
    /// Which place is being asked for right after a habit is turned on ("Gym", "Work", "School").
    @State private var asking: AskPlace?
    fileprivate struct AskPlace: Identifiable { var id: String }
    @State private var run = false
    @State private var walk = true
    @State private var journal = true
    @State private var work = true
    @State private var school = false
    @State private var read = false
    @State private var meditate = false
    @State private var water = false
    @State private var wake = UserSchedule.date(7 * 60, on: .now)
    @State private var bed = UserSchedule.date(23 * 60, on: .now)
    @State private var gymTime = UserSchedule.date(18 * 60, on: .now)

    fileprivate struct Habit: Identifiable {
        var id: String { title }
        var title: String; var symbol: String; var detail: String; var on: Binding<Bool>
    }
    private var habits: [Habit] {
        [Habit(title: "Gym", symbol: "dumbbell.fill", detail: "A visit to your gym", on: $gym),
         Habit(title: "Run", symbol: "figure.run", detail: "Running workouts from Apple Health", on: $run),
         Habit(title: "Walk", symbol: "figure.walk", detail: "About 20 min of walking · steps set from your Health data", on: $walk),
         Habit(title: "Journal", symbol: "book.closed.fill", detail: "A journal entry, photo, or voice memo", on: $journal),
         Habit(title: "Work", symbol: "briefcase.fill", detail: "Being at work during your hours", on: $work),
         Habit(title: "School", symbol: "graduationcap.fill", detail: "Being at school during class hours", on: $school),
         Habit(title: "Read", symbol: "books.vertical.fill", detail: "Time reading", on: $read),
         Habit(title: "Meditate", symbol: "brain.head.profile", detail: "Mindful minutes from Apple Health", on: $meditate),
         Habit(title: "Drink Water", symbol: "drop.fill", detail: "Water logged in Apple Health", on: $water)]
    }

    @ViewBuilder private func icon(_ s: String) -> some View {
        if style == "1" {
            // iOS Settings icon: white glyph on a filled rounded square.
            Image(systemName: s).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                .frame(width: 29, height: 29).background(Theme.accent, in: .rect(cornerRadius: 7, style: .continuous))
        } else {
            Image(systemName: s).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30).background(Theme.accent.opacity(0.14), in: .circle)
        }
    }
    @ViewBuilder private func placeRow(_ title: String, _ symbol: String, _ value: String) -> some View {
        if style == "1" {
            NavigationLink { EmptyView() } label: {
                LabeledContent { Text(value).lineLimit(1) } label: { Label { Text(title) } icon: { icon(symbol) } }
            }
        } else {
        HStack(spacing: 12) {
            icon(symbol)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(value == "Add" ? Theme.accent : .secondary).lineLimit(1)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        }
    }
    private func place(for title: String) -> String? {
        switch title { case "Gym": gymPlace; case "Work": workPlace; case "School": schoolPlace; default: nil }
    }
    private func habitToggle(_ h: Habit, detail: Bool = true) -> some View {
        Group {
        if style == "1" {
            // One line per row, like a switch in iOS Settings. The place shows in Places below.
            Toggle(isOn: h.on.animation()) { Label { Text(h.title) } icon: { icon(h.symbol) } }
        } else {
        Toggle(isOn: h.on.animation()) {
            HStack(spacing: 12) {
                icon(h.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.title)
                    if style == "1", h.on.wrappedValue, let p = place(for: h.title) {
                        Label(p, systemImage: "mappin").font(.footnote).foregroundStyle(Theme.accent)
                    } else if detail { Text(h.detail).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        }
        }
        .accessibilityIdentifier("habit-\(h.title)")
    }
    private var addPlaceMenu: some View {
        Menu {
            if !gym { Button("Gym", systemImage: "dumbbell") {} }
            if !school { Button("School", systemImage: "graduationcap") {} }
            Button("Custom Place…", systemImage: "mappin") {}
        } label: {
            if style == "1" { Text("Add Place\u{2026}").foregroundStyle(Theme.accent) } else { Label("Add Place", systemImage: "plus") }
        }
    }

    @ViewBuilder private var placesSection: some View {
        Section {
            placeRow("Home", "house.fill", "E 34th St")
            if gym { placeRow("Gym", "dumbbell.fill", gymPlace ?? "Add") }
            if work { placeRow("Work", "briefcase.fill", workPlace ?? "Add") }
            if school { placeRow("School", "graduationcap.fill", schoolPlace ?? "Add") }
            placeRow("Grandpa\u{2019}s House", "mappin", "Kew Gardens")
            addPlaceMenu
        } header: { Text("Places") } footer: {
            Text("Home comes first. A place for Gym, Work, or School only shows when that habit is on.")
        }
    }
    @ViewBuilder private var timesSection: some View {
        Section("Times") {
            DatePicker("Wake Up", selection: $wake, displayedComponents: .hourAndMinute)
            DatePicker("Bedtime", selection: $bed, displayedComponents: .hourAndMinute)
            if work { LabeledContent("Work") { Text("Mon – Fri, 9:00 AM – 5:00 PM") } }
            if gym { DatePicker("Gym Time", selection: $gymTime, displayedComponents: .hourAndMinute).accessibilityIdentifier("gymTime") }
            if school { LabeledContent("Classes") { Text("Mon – Fri, 8:30 AM – 3:00 PM") } }
        }
    }
    @ViewBuilder private var habitsSection: some View {
        Section {
            ForEach(habits) { habitToggle($0) }
        } header: { Text("My Habits") } footer: {
            Text("Your day score and your Today schedule use what\u{2019}s on.")
        }
    }

    var body: some View {
        Form {
            switch style {
            case "1": habitsSection; placesSection; timesSection
            case "2": placesSection; timesSection; habitsSection
            case "3": perHabit
            case "4": summaryTop; habitsSection; placesSection
            case "5": drillDown
            case "6": chips; placesSection; timesSection
            case "7": dayLine; habitsSection; placesSection
            default: placesSection; compactHabits; timesSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackgroundView())
        .navigationTitle("Your Schedule")
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settingsSample")
        .onChange(of: gym) { _, on in if style == "1", on, gymPlace == nil { asking = AskPlace(id: "Gym") } }
        .onChange(of: work) { _, on in if style == "1", on, workPlace == nil { asking = AskPlace(id: "Work") } }
        .onChange(of: school) { _, on in if style == "1", on, schoolPlace == nil { asking = AskPlace(id: "School") } }
        .sheet(item: $asking, onDismiss: {
            // Cancelled without a place: the habit goes back off.
            if gym && gymPlace == nil { gym = false }
            if work && workPlace == nil { work = false }
            if school && schoolPlace == nil { school = false }
        }) { a in
            NavigationStack {
                AddPlaceView(title: "Your \(a.id)", prompt: "Search for your \(a.id.lowercased())",
                             categories: a.id == "Gym" ? [.fitnessCenter] : a.id == "School" ? [.school, .university] : nil) { item in
                    let name = item.name ?? a.id
                    withAnimation {
                        switch a.id { case "Gym": gymPlace = name; case "Work": workPlace = name; default: schoolPlace = name }
                    }
                }
            }
        }
    }

    /// 3: Home and sleep on top, then each habit with its own place and time inside it.
    @ViewBuilder private var perHabit: some View {
        Section {
            placeRow("Home", "house.fill", "E 34th St")
            DatePicker("Wake Up", selection: $wake, displayedComponents: .hourAndMinute)
            DatePicker("Bedtime", selection: $bed, displayedComponents: .hourAndMinute)
        } header: { Text("Home") }
        Section {
            habitToggle(habits[0], detail: false)
            if gym {
                placeRow("Location", "mappin", "Iron Works Gym")
                DatePicker("Usual Time", selection: $gymTime, displayedComponents: .hourAndMinute)
            }
        } header: { Text("Gym") }
        Section {
            habitToggle(habits[4], detail: false)
            if work {
                placeRow("Location", "mappin", "Park Ave S")
                LabeledContent("Hours") { Text("Mon – Fri, 9 – 5") }
            }
        } header: { Text("Work") }
        Section {
            habitToggle(habits[5], detail: false)
        } header: { Text("School") }
        Section("More Habits") {
            ForEach([habits[1], habits[2], habits[3], habits[6]]) { habitToggle($0) }
        }
    }

    /// 4: a summary card up top with home and the day's times.
    @ViewBuilder private var summaryTop: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    icon("house.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Home").font(.headline)
                        Text("E 34th St, New York").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 0) {
                    stat("Wake", "7:00 AM"); stat("Work", "9 – 5"); stat("Gym", "6:00 PM"); stat("Bed", "11:00 PM")
                }
            }
            .padding(.vertical, 4)
        }
    }
    private func stat(_ t: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(t).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    /// 5: like Settings, three rows that each open their own page.
    @ViewBuilder private var drillDown: some View {
        Section {
            NavigationLink { Form { placesSection } } label: { row("Places", "mappin.and.ellipse", "Home, Gym, Work +1") }
            NavigationLink { Form { timesSection } } label: { row("Times", "clock.fill", "7:00 AM – 11:00 PM") }
            NavigationLink { Form { habitsSection } } label: { row("My Habits", "checkmark.circle.fill", "Gym, Walk, Journal, Work") }
        } footer: { Text("Your Today schedule is built from these.") }
    }
    private func row(_ t: String, _ s: String, _ v: String) -> some View {
        HStack(spacing: 12) {
            icon(s)
            VStack(alignment: .leading, spacing: 2) {
                Text(t)
                Text(v).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// 6: habits as buttons you tap on and off.
    @ViewBuilder private var chips: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(habits) { h in
                    Button { h.on.wrappedValue.toggle() } label: {
                        VStack(spacing: 6) {
                            Image(systemName: h.symbol).font(.system(size: 18, weight: .semibold))
                            Text(h.title).font(.footnote.weight(.semibold)).lineLimit(1)
                        }
                        .foregroundStyle(h.on.wrappedValue ? Color.white : Theme.accent)
                        .frame(maxWidth: .infinity).frame(height: 64)
                        .background(h.on.wrappedValue ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.12)),
                                    in: .rect(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        } header: { Text("My Habits") } footer: { Text("Tap to turn a habit on or off.") }
    }

    /// 7: your day in order, wake to bed, with the habits' times on it.
    @ViewBuilder private var dayLine: some View {
        Section("Your Day") {
            ForEach(dayItems.indices, id: \.self) { i in
                let item = dayItems[i]
                HStack(spacing: 12) {
                    Text(item.1).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    icon(item.2)
                    Text(item.0)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        }
    }
    private var dayItems: [(String, String, String)] {
        var out = [("Wake Up", "7:00 AM", "sun.max.fill")]
        if work { out.append(("Work", "9:00 AM", "briefcase.fill")) }
        if gym { out.append(("Gym", "6:00 PM", "dumbbell.fill")) }
        out.append(("Bedtime", "11:00 PM", "moon.fill"))
        return out
    }

    /// 8: short habit rows (details only for Walk and Run), places and times around them.
    @ViewBuilder private var compactHabits: some View {
        Section("My Habits") {
            ForEach(habits) { h in habitToggle(h, detail: h.title == "Walk" || h.title == "Run") }
        }
    }
}
