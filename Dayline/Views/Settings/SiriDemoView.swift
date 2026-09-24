import SwiftUI
import MapKit

/// Hidden page (long-press "Your data" in Profile) that shows every Dayline Siri command
/// and its answer in the iOS 27 Siri look, so the demo recording can show them.
struct SiriDemoView: View {
    private struct Item: Identifiable {
        let id = UUID()
        let ask: String
        let reply: String
        let card: AnyView
    }

    private var items: [Item] {
        let photos = ["demo-coffee", "demo-park"].compactMap { name -> Data? in
            guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") else { return nil }
            return try? Data(contentsOf: url)
        }
        return [
            Item(ask: "Journal my last two photos in Dayline",
                 reply: "Done. I added 2 photos and your note to today's journal.",
                 card: AnyView(JournalSnippetView(photos: photos, note: "Today was a good day.", detail: "Today · 12:40 PM · Blue Door Coffee"))),
            Item(ask: "How's Sam's streak in Dayline",
                 reply: "Sam is on a 9-day streak, you're at 6.",
                 card: AnyView(FriendScoreSnippetView(name: "Sam", color: Color(red: 1, green: 0.27, blue: 0.23), streak: 9, best: 14, yourStreak: 6))),
            Item(ask: "Take me back to where I ate on Sunday",
                 reply: "You had dinner at Lucia Trattoria. It's 12 minutes away.",
                 card: AnyView(DemoRouteCard())),
            Item(ask: "What's my day score in Dayline",
                 reply: "You're at 74, on track. A walk tonight gets you past 85.",
                 card: AnyView(DayScoreSnippetView(score: 74, label: "On track", tip: "30-min walk tonight → 85+",
                                                   factors: [("Woke up on time", 14), ("Gym", 18), ("Late night", -6)]))),
            Item(ask: "Where was I yesterday at 3 PM in Dayline",
                 reply: "You were at the Office, from 1:10 to 5:40 PM.",
                 card: AnyView(WhereWasISnippetView(name: "Office", timeText: "Tuesday · 1:10 – 5:40 PM", note: "Voice note: “Project draft done”", map: nil))),
            Item(ask: "What's my streak in Dayline",
                 reply: "6 days in a row. Sam and Jordan are ahead of you.",
                 card: AnyView(StreakSnippetView(days: 6, best: 9, rows: [("Sam", Color(red: 1, green: 0.27, blue: 0.23), 9),
                                                                          ("Jordan", Color(red: 0.19, green: 0.82, blue: 0.35), 7),
                                                                          ("You", Theme.accent, 6)]))),
        ]
    }

    @State private var index = 0

    var body: some View {
        let item = items[index]
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Color.green.opacity(0.35), .clear], center: .bottom, startRadius: 0, endRadius: 260)
                .ignoresSafeArea().allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 18) {
                Text(item.ask)
                    .font(.body).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color(white: 0.17), in: .rect(cornerRadius: 22, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 40)
                Text(item.reply).font(.title3).foregroundStyle(.white).padding(.horizontal, 8)
                item.card
                Spacer()
            }
            .padding(.horizontal, 18)
            .id(index)
            .transition(.opacity)
            HStack(spacing: 10) {
                Button { withAnimation { index = (index + items.count - 1) % items.count } } label: {
                    Image(systemName: "chevron.left").frame(width: 46, height: 46)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                Text("\(index + 1) of \(items.count) · Ask Siri").foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .glassEffect(.regular, in: .capsule)
                Button { withAnimation { index = (index + 1) % items.count } } label: {
                    Image(systemName: "chevron.right").frame(width: 46, height: 46)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityIdentifier("siriNext")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.bottom, 10)
        }
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { WidgetsDemoView().preferredColorScheme(.light) } label: { Text("Widgets") }
                    .accessibilityIdentifier("widgetsDemoLink")
            }
        }
        .navigationTitle("")
        .backgroundNavBar()
        .toolbarVisibility(.hidden, for: .tabBar)
        .accessibilityIdentifier("siriDemo")
    }
}

/// Take-me-back card for the demo: a real MapKit map with a route line and a Go button.
private struct DemoRouteCard: View {
    @State private var route: RouteSnapshot?
    private let place = CLLocationCoordinateHelper.lucia
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SiriAppLine()
            ZStack {
                if let route, let img = UIImage(data: route.image) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color(white: 0.12)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 170).clipped()
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Text(route?.etaText ?? "12 min").font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(.black.opacity(0.7), in: .capsule).padding(10)
            }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lucia Trattoria").font(.headline)
                    Text(route?.detailText ?? "12 min").font(.footnote).foregroundStyle(.white.opacity(0.6))
                    Text("Last visit Sunday 7:55 PM").font(.footnote).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Text("Go").font(.body.weight(.bold)).padding(.horizontal, 22).padding(.vertical, 9).background(Color.green, in: .capsule)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .task { route = await RouteSnapshot.make(to: place.to, name: "Lucia Trattoria", from: place.from) }
    }
}

enum CLLocationCoordinateHelper {
    /// Demo route in Manhattan (matches the demo timeline area).
    static let lucia = (from: CLLocationCoordinate2D(latitude: 40.7359, longitude: -73.9911),
                        to: CLLocationCoordinate2D(latitude: 40.7505, longitude: -73.9772))
}
