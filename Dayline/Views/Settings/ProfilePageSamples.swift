import SwiftUI

/// "profile.page" 1-5: sample layouts for the Profile page (rows are look-only except Your Schedule).
/// 1 = a plain iOS Settings list. 2 = a header with your streak and average, then rows.
/// 3 = big tiles for the main pages, then rows. 4 = two groups only (Your Day, App).
/// 5 = a search field on top, like iOS Settings.
struct ProfilePageSample: View {
    var page: String
    @State private var query = ""

    private struct Item: Identifiable { var id: String { title }; var title: String; var symbol: String; var value: String = "" }
    private let dayItems = [Item(title: "Your Schedule", symbol: "clock.fill", value: "7:00 AM – 11:00 PM"),
                            Item(title: "Places", symbol: "mappin.and.ellipse", value: "Home · Work"),
                            Item(title: "My Habits", symbol: "checkmark.circle.fill", value: "4 on")]
    private let appItems = [Item(title: "Notifications", symbol: "bell.fill"),
                            Item(title: "Appearance", symbol: "circle.lefthalf.filled", value: "System"),
                            Item(title: "Location", symbol: "location.fill", value: "Every 5 min"),
                            Item(title: "Siri & Shortcuts", symbol: "mic.fill"),
                            Item(title: "Privacy", symbol: "hand.raised.fill")]

    private func icon(_ s: String) -> some View {
        Image(systemName: s).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
            .frame(width: 30, height: 30).background(Theme.accent.opacity(0.14), in: .circle)
    }
    @ViewBuilder private func link(_ it: Item) -> some View {
        NavigationLink {
            if it.title == "Your Schedule" { YourScheduleEntry() } else { Text(it.title).navigationTitle(it.title) }
        } label: {
            HStack(spacing: 12) {
                icon(it.symbol)
                Text(it.title)
                Spacer()
                Text(it.value).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityIdentifier(it.title == "Your Schedule" ? "yourScheduleRow" : it.title)
    }
    private var account: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 54)).symbolRenderingMode(.hierarchical).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sign In").font(.title3.weight(.semibold))
                Text("Back up your timeline").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        Form {
            Section { TabTitle("Profile") }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            if page == "5" {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search", text: $query)
                    }
                }
            }
            switch page {
            case "1":
                Section { account }
                Section { ForEach(dayItems) { link($0) } }
                Section { ForEach(appItems) { link($0) } }
            case "2":
                Section {
                    VStack(spacing: 12) {
                        account
                        HStack(spacing: 0) {
                            stat("Streak", "6 days"); stat("Average", "71"); stat("Places", "14")
                        }
                    }
                }
                Section("Your Day") { ForEach(dayItems) { link($0) } }
                Section("App") { ForEach(appItems) { link($0) } }
            case "3":
                Section { account }
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(dayItems + [appItems[0]]) { it in
                            NavigationLink {
                                if it.title == "Your Schedule" { YourScheduleEntry() } else { Text(it.title) }
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    icon(it.symbol)
                                    Text(it.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(it.title == "Your Schedule" ? "yourScheduleRow" : it.title)
                        }
                    }
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                Section { ForEach(appItems.dropFirst()) { link($0) } }
            case "4":
                Section { account }
                Section("Your Day") { ForEach(dayItems) { link($0) } }
                Section("App") { ForEach([appItems[0], appItems[1], appItems[4]]) { link($0) } }
            default:
                Section { account }
                Section { ForEach((dayItems + appItems).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { link($0) } }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackgroundView())
        .navigationTitle("Profile")
        .tabRoot()
    }
    private func stat(_ t: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline).monospacedDigit()
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
