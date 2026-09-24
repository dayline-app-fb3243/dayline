import SwiftUI

/// "journal.page" 1-5: sample layouts for the Journal page.
/// 1 = a photo grid like Photos (entries without photos as small tiles). 2 = a compact list, one row per entry.
/// 3 = one card per day holding all its entries. 4 = a week strip on top, then that day's entries.
/// 5 = a line through the day with times on the left.
struct JournalPageSample: View {
    var page: String
    var days: [(Date, [JournalGroup])]
    var onTap: (JournalGroup) -> Void
    @State private var pickedDay: Date?

    private static let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()
    private func dayTitle(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? "Today" : d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
    private func heading(_ g: JournalGroup) -> String {
        g.title ?? g.place ?? (g.kind == .voice ? "Voice memo" : g.kind == .photo ? "Photo" : "Journal entry")
    }
    private func symbol(_ g: JournalGroup) -> String { g.kind == .voice ? "mic.fill" : g.kind == .photo ? "photo" : "pencil" }
    private func thumb(_ g: JournalGroup, _ size: CGFloat) -> some View {
        Group {
            if let d = g.photos.first, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: symbol(g)).font(.system(size: size * 0.32, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.accent.opacity(0.12))
            }
        }
        .frame(width: size, height: size).clipShape(.rect(cornerRadius: size * 0.18, style: .continuous))
    }
    private func dayHeader(_ d: Date) -> some View {
        Text(dayTitle(d)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4).padding(.top, 6)
    }

    var body: some View {
        switch page {
        case "1": grid
        case "2": list
        case "3": dayCards
        case "4": weekStrip
        default: line
        }
    }

    private var grid: some View {
        ForEach(days, id: \.0) { day, groups in
            dayHeader(day)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(groups) { g in
                    Button { onTap(g) } label: {
                        GeometryReader { geo in thumb(g, geo.size.width) }.aspectRatio(1, contentMode: .fit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ g: JournalGroup) -> some View {
        HStack(spacing: 12) {
            thumb(g, 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(heading(g)).font(.body.weight(.semibold)).lineLimit(1)
                Text(g.text ?? g.place ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Self.clock.string(from: g.date)).font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }

    private var list: some View {
        ForEach(days, id: \.0) { day, groups in
            dayHeader(day)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                        Button { onTap(g) } label: { row(g) }.buttonStyle(.plain)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                        if i < groups.count - 1 { Divider().padding(.leading, 74) }
                    }
                }
            }
        }
    }

    private var dayCards: some View {
        ForEach(days, id: \.0) { day, groups in
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(dayTitle(day)).font(.title3.bold())
                        Spacer()
                        Text("\(groups.count) \(groups.count == 1 ? "entry" : "entries")").font(.subheadline).foregroundStyle(.secondary)
                    }
                    let pics = groups.flatMap(\.photos).prefix(4)
                    if !pics.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(pics.enumerated()), id: \.offset) { _, d in
                                if let img = UIImage(data: d) {
                                    Image(uiImage: img).resizable().scaledToFill().frame(height: 80).frame(maxWidth: .infinity)
                                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }
                    ForEach(groups.filter { $0.photos.isEmpty }) { g in
                        Button { onTap(g) } label: {
                            Label(g.text ?? heading(g), systemImage: symbol(g)).font(.subheadline).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var weekStrip: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let week = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let selected = pickedDay ?? days.first?.0 ?? today
        let groups = days.first { cal.isDate($0.0, inSameDayAs: selected) }?.1 ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(week, id: \.self) { d in
                    let has = days.contains { cal.isDate($0.0, inSameDayAs: d) }
                    let on = cal.isDate(d, inSameDayAs: selected)
                    Button { pickedDay = d } label: {
                        VStack(spacing: 4) {
                            Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            Text(d.formatted(.dateTime.day())).font(.subheadline.weight(.semibold))
                                .foregroundStyle(on ? .white : .primary)
                                .frame(width: 36, height: 36).background(on ? Theme.accent : .clear, in: .circle)
                            Circle().fill(has ? Theme.accent : .clear).frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8).background(.background, in: .rect(cornerRadius: 20, style: .continuous))
            dayHeader(selected)
            ForEach(groups) { g in
                Button { onTap(g) } label: { JournalCard(group: g) }.buttonStyle(.plain)
            }
        }
    }

    private var line: some View {
        ForEach(days, id: \.0) { day, groups in
            dayHeader(day)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                    HStack(alignment: .top, spacing: 10) {
                        Text(Self.clock.string(from: g.date)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: 62, alignment: .trailing).padding(.top, 14)
                        VStack(spacing: 0) {
                            Rectangle().fill(i == 0 ? .clear : Theme.accent.opacity(0.35)).frame(width: 2, height: 14)
                            Circle().fill(Theme.accent).frame(width: 10, height: 10)
                            Rectangle().fill(i == groups.count - 1 ? .clear : Theme.accent.opacity(0.35)).frame(width: 2).frame(maxHeight: .infinity)
                        }
                        Button { onTap(g) } label: { JournalCard(group: g) }.buttonStyle(.plain).padding(.vertical, 5)
                    }
                }
            }
        }
    }
}
