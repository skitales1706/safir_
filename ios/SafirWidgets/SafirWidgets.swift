import SwiftUI
import WidgetKit

/// Home-screen widgets (Android widget/SafirWidgets.kt): "Safir" (weather + rates) and a small
/// weather one. They draw the snapshot the app keeps in the App Group (Core/WidgetSnapshot.swift)
/// and ask for a redraw every 30 minutes; the app reloads them whenever Services refresh.
@main
struct SafirWidgetBundle: WidgetBundle {
    var body: some Widget {
        SafirWidget()
        WeatherWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

private enum Brand {
    static let top = Color(red: 0.12, green: 0.81, blue: 0.94)
    static let bottom = Color(red: 0.16, green: 0.36, blue: 0.85)
    static var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct SafirWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SafirWidget", provider: SnapshotProvider()) { entry in
            SafirWidgetView(entry: entry)
                .containerBackground(for: .widget) { Brand.gradient }
        }
        .configurationDisplayName("Safir")
        .description("Погода и курсы валют НБТ.")
        .supportedFamilies([.systemMedium])
    }
}

struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SafirWeatherWidget", provider: SnapshotProvider()) { entry in
            WeatherWidgetView(entry: entry)
                .containerBackground(for: .widget) { Brand.gradient }
        }
        .configurationDisplayName("Погода")
        .description("Погода в выбранном городе.")
        .supportedFamilies([.systemSmall])
    }
}

private struct WeatherBlock: View {
    let s: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.city).font(.headline).lineLimit(1)
            Image(systemName: WidgetSnapshot.symbol(code: s.code, day: s.isDay))
                .symbolRenderingMode(.multicolor).font(.system(size: 30))
            Text(s.temp.map { "\($0)°" } ?? "—").font(.system(size: 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "cloud.sun.fill").font(.title2)
            Text("Откройте Safir → Сервисы").font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
    }
}

struct SafirWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let s = entry.snapshot {
            HStack(spacing: 14) {
                WeatherBlock(s: s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Link(destination: URL(string: "safir://services/rates")!) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(s.rates.prefix(3), id: \.code) { rate in
                            HStack(spacing: 6) {
                                Text(rate.flag)
                                Text(rate.code).font(.caption.weight(.semibold))
                                Spacer(minLength: 4)
                                Text(String(format: rate.perUnit < 1 ? "%.4f" : "%.2f", rate.perUnit))
                                    .font(.callout.weight(.bold)).monospacedDigit()
                            }
                        }
                        if s.updated > 0 {
                            Text(Date(timeIntervalSince1970: s.updated), style: .time)
                                .font(.caption2).opacity(0.7)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.16)))
                }
                .frame(maxWidth: .infinity)
            }
            .widgetURL(URL(string: "safir://services/weather"))
        } else {
            EmptyState()
        }
    }
}

struct WeatherWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let s = entry.snapshot {
                WeatherBlock(s: s).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EmptyState()
            }
        }
        .widgetURL(URL(string: "safir://services/weather"))
    }
}
