import SwiftUI

/// Hidden demo page (from the Siri demo) that draws Dayline's widgets exactly as the
/// widget extension does, on a Home Screen and Lock Screen, so the recording can show them.
struct WidgetsDemoView: View {
    private let snap = WidgetSnapshot(date: .now, score: 86, hasDayData: true, label: "Great day!", summary: "Up early, gym done.",
                                      nextTitle: "Gym", nextStart: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now),
                                      streakDays: 6, recentScores: [72, 85, 90, 64, 88, 91, 86],
                                      friendTags: [.init(initial: "S", red: 1, green: 0.23, blue: 0.19),
                                                   .init(initial: "J", red: 0.2, green: 0.78, blue: 0.35)])

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(spacing: 0) {
                    tile("Today") { card(width: 170, blue: true) { TodaySmallWidgetContent(s: snap) } }
                    Spacer()
                    tile("Streak") { card(width: 170, blue: false) { StreakWidgetContent(s: snap) } }
                }
                tile("Today (wide)") { card(width: 354, blue: true) { TodayWideWidgetContent(s: snap) } }
            }
            .padding(.horizontal, 24).padding(.top, 20)
            Spacer()
            VStack(spacing: 6) {
                Text("Lock Screen").font(.subheadline.weight(.semibold)).opacity(0.85)
                Text("9:41").font(.scaled(size: 72, weight: .bold))
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(.white.opacity(0.18))
                        WidgetRing(score: 86, lineWidth: 6, showsNumber: false).frame(width: 56, height: 56)
                        Text("86").font(.scaled(size: 18, weight: .bold))
                    }
                    .frame(width: 66, height: 66)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Day score 86").font(.subheadline.weight(.semibold))
                        Text("Next: Gym 6:00 PM").font(.footnote.weight(.medium)).opacity(0.85)
                    }
                    .padding(.horizontal, 12).frame(width: 160, height: 66, alignment: .leading)
                    .background(.white.opacity(0.18), in: .rect(cornerRadius: 14))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 22)
            .background(LinearGradient(colors: [Color(red: 0.11, green: 0.2, blue: 0.47), Color(red: 0.23, green: 0.39, blue: 0.85)],
                                       startPoint: .top, endPoint: .bottom))
        }
        .background(LinearGradient(colors: [Color(red: 0.61, green: 0.75, blue: 1), Color(red: 0.93, green: 0.94, blue: 0.98)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .navigationTitle("Widgets")
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .accessibilityIdentifier("widgetsDemo")
    }

    private func tile<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 6) { c(); Text(label).font(.caption.weight(.medium)) }
    }

    private func card<C: View>(width: CGFloat, blue: Bool, @ViewBuilder _ c: () -> C) -> some View {
        c().padding(16)
            .frame(width: width, height: 170)
            .background {
                if blue {
                    ZStack(alignment: .topTrailing) { widgetBlueCard; WidgetBubble(size: 130).offset(x: 40, y: -40) }
                } else {
                    Color(.systemBackground)
                }
            }
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }
}
