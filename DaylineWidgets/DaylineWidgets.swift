import WidgetKit
import SwiftUI
import AppIntents

struct DayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { DayEntry(date: .now, snapshot: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(DayEntry(date: .now, snapshot: SharedStore.load() ?? .placeholder))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let entry = DayEntry(date: .now, snapshot: SharedStore.load() ?? .placeholder)
        // The app reloads widgets whenever the score changes; this is just a fallback refresh.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(s.score), in: 0...100) { Text("Day") } currentValueLabel: { Text("\(s.score)") }
                .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Day score \(s.score)").font(.headline)
                if let next = s.nextTitle, let start = s.nextStart {
                    Text("Next: \(next) \(start.formatted(date: .omitted, time: .shortened))").font(.caption)
                } else {
                    Text(s.label).font(.caption)
                }
            }
        case .systemSmall:
            TodaySmallWidgetContent(s: s)
        default:
            TodayWideWidgetContent(s: s)
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: DayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    ZStack(alignment: .topTrailing) { widgetBlueCard; WidgetBubble(size: 130).offset(x: 40, y: -40) }
                }
                .widgetURL(URL(string: "dayline://today"))
        }
        .configurationDisplayName("Today")
        .description("Your day score and what's next.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct StreakWidgetView: View {
    let entry: DayEntry
    var body: some View { StreakWidgetContent(s: entry.snapshot) }
}

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StreakWidget", provider: DayProvider()) { entry in
            StreakWidgetView(entry: entry).containerBackground(.background, for: .widget)
                .widgetURL(URL(string: "dayline://streak"))
        }
        .configurationDisplayName("Streak")
        .description("Days in a row on schedule with a score of 80 or more.")
        .supportedFamilies([.systemSmall])
    }
}

/// Lock screen / Control Center button to jump straight into a voice note.
struct VoiceNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.dayline.voice") {
            ControlWidgetButton(action: OpenVoiceIntent()) {
                Label("Voice note", systemImage: "mic.fill")
            }
        }
        .displayName("Dayline voice note")
    }
}

struct OpenVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Voice Note"
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "dayline://voice")!))
    }
}

@main
struct DaylineWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        StreakWidget()
        VoiceNoteControl()
    }
}
