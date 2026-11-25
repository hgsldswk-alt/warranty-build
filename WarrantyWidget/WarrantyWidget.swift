import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let today: Day
    let items: [Item]
    let pro: Bool
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), today: .today, items: [], pro: true) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let next = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400)).addingTimeInterval(60)
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> Entry {
        let state = Store.load() ?? AppState()
        let today = Day.today
        let upcoming = state.sorted(on: today).filter { ($0.next(after: today)?.day ?? today) >= today && !$0.deadlines.isEmpty }
        return Entry(date: Date(), today: today, items: Array(upcoming.prefix(3)), pro: state.entitlement.hasPro(at: Date()))
    }
}

struct WidgetView: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L.t("widget.title"), systemImage: "calendar.badge.clock")
                .font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
            if !entry.pro {
                widgetPlaceholder(L.t("widget.locked"), icon: "lock")
            } else if entry.items.isEmpty {
                widgetPlaceholder(L.t("widget.empty"), icon: "calendar")
            } else {
                ForEach(entry.items) { item in
                    if let d = item.next(after: entry.today) {
                        let mark = CategoryMark(item.category)
                        HStack(spacing: 5) {
                            IconGlyph(icon: mark.icon, tone: mark.tone, size: 22)
                            Text(item.displayName).font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 0)
                            StatusPill(title: Remaining.text(from: entry.today, to: d.day),
                                       tone: AccentTone.deadline(days: entry.today.days(until: d.day)))
                                .lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.ink)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Theme.paper, Theme.background], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(Launch.openURL)
    }

    private func widgetPlaceholder(_ title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            EmptyIllustration(icon: icon, size: 48)
            Text(title).font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

@main
struct WarrantyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Launch.widgetKind, provider: Provider()) { WidgetView(entry: $0) }
            .configurationDisplayName(L.t("widget.title"))
            .description(L.t("widget.desc"))
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
