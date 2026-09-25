import SwiftUI

/// Preview of app-matched widget options, in both system appearances.
struct WidgetDesignGalleryView: View {
    let design: WidgetDesign
    let page: Int
    private let friends = DaylineWidgetFriend.preview
    private var dark: Bool { page == 2 }
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("\(design.id). \(design.name)").font(.headline)
                Text(design.note).font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    card(170, 170) { WidgetScoreOption(d: design, score: 86, wide: false) }
                    card(170, 170) { WidgetFriendsOption(d: design, days: 6, friends: friends, wide: false) }
                }
                card(352, 170) { WidgetScoreOption(d: design, score: 86, wide: true) }
                card(352, 170) { WidgetFriendsOption(d: design, days: 6, friends: friends, wide: true) }
                Text(dark ? "Dark appearance" : "Light appearance")
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 6)
                Spacer(minLength: 0)
            }
            .padding(.top, 66)
        }
        .environment(\.colorScheme, dark ? .dark : .light)
    }
    private func card<C: View>(_ width: CGFloat, _ height: CGFloat, @ViewBuilder content: () -> C) -> some View {
        content().padding(14).frame(width: width, height: height)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
    }
}
