import MenewShared
import SwiftUI
import WidgetKit

/// Os widgets do Menew (mesa e Central de Notificações). Leem o arquivo que o app escreve a cada minuto.
@main
struct MenewWidgets: WidgetBundle {
    var body: some Widget {
        SystemWidget()
        MeetingsWidget()
        TimersWidget()
        ScreenTimeWidget()
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

/// Uma entrada agora e outra a cada mudança que importa (início e fim de reunião, fim de timer)
struct Provider: TimelineProvider {
    /// De quanto em quanto tempo pedir dados novos ao arquivo
    let refresh: TimeInterval
    var changes: (WidgetSnapshot, Date) -> [Date] = { _, _ in [] }

    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snap: .demo(lang: WL.system)) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        // Na galeria, os dados de exemplo; na mesa, os de verdade
        completion(Entry(date: Date(), snap: context.isPreview ? .demo(lang: WL.system) : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let snap = WidgetSnapshot.load()
        let next = now.addingTimeInterval(refresh)
        let dates = [now] + (snap.map { changes($0, now) } ?? []).filter { $0 > now && $0 < next }.sorted()
        completion(Timeline(entries: dates.map { Entry(date: $0, snap: snap) }, policy: .after(next)))
    }
}

/// Fundo padrão e o toque abre o Menew
private struct Frame<Content: View>: View {
    let entry: Entry
    let path: String
    @ViewBuilder var content: (WidgetSnapshot) -> Content

    var body: some View {
        Group {
            if let s = entry.snap {
                content(s)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "menubar.rectangle").font(.system(size: 22)).foregroundStyle(.secondary)
                    Text(WL.s("Abra o Menew", WL.system)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "menew://\(path)"))
    }
}

private func size(_ f: WidgetFamily) -> WidgetSize { f == .systemSmall ? .small : .medium }

struct SystemWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "system", provider: Provider(refresh: 5 * 60)) { e in
            SystemEntryView(entry: e)
        }
        .configurationDisplayName(WL.s("Sistema", WL.system))
        .description(WL.s("CPU, memória, disco e bateria.", WL.system))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SystemEntryView: View {
    let entry: Entry
    @Environment(\.widgetFamily) var family
    var body: some View { Frame(entry: entry, path: "system") { SystemWidgetView($0, size: size(family)) } }
}

struct MeetingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "meetings", provider: Provider(refresh: 15 * 60) { s, _ in s.meetings.flatMap { [$0.start, $0.end] } }) { e in
            MeetingsEntryView(entry: e)
        }
        .configurationDisplayName(WL.s("Reuniões", WL.system))
        .description(WL.s("A próxima reunião e o resto do dia.", WL.system))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MeetingsEntryView: View {
    let entry: Entry
    @Environment(\.widgetFamily) var family
    var body: some View { Frame(entry: entry, path: "meetings") { MeetingsWidgetView($0, size: size(family), now: entry.date) } }
}

struct TimersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "timers", provider: Provider(refresh: 15 * 60) { s, _ in s.countdowns.map(\.end) }) { e in
            TimersEntryView(entry: e)
        }
        .configurationDisplayName(WL.s("Timers", WL.system))
        .description(WL.s("Foco e timers contando ao vivo.", WL.system))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TimersEntryView: View {
    let entry: Entry
    @Environment(\.widgetFamily) var family
    var body: some View { Frame(entry: entry, path: "timers") { TimersWidgetView($0, size: size(family), now: entry.date) } }
}

struct ScreenTimeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "screentime", provider: Provider(refresh: 15 * 60)) { e in
            ScreenTimeEntryView(entry: e)
        }
        .configurationDisplayName(WL.s("Tempo de tela", WL.system))
        .description(WL.s("Quanto tempo você passou em cada app hoje.", WL.system))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ScreenTimeEntryView: View {
    let entry: Entry
    @Environment(\.widgetFamily) var family
    var body: some View { Frame(entry: entry, path: "screentime") { ScreenTimeWidgetView($0, size: size(family)) } }
}
