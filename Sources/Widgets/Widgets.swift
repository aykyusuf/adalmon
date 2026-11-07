import SwiftUI
import WidgetKit

struct AllBatteriesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetShared.Kind.allBatteries, intent: AllBatteriesIntent.self, provider: AllBatteriesProvider()) { entry in
            AllBatteriesEntryView(entry: entry)
                .widgetURL(AdalmonRoute.battery.url)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tüm piller")
        .description("Mac'in ve aksesuarlarının pilleri: halkalar, liste ya da çubuklar.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct AllBatteriesEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            AllBatteriesWidgetView(snapshot: snapshot, options: entry.options, size: family.adalmonSize ?? .small, now: entry.date)
        } else {
            WidgetNoDataView()
        }
    }
}

struct MacBatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.Kind.macBattery, provider: SnapshotProvider()) { entry in
            MacBatteryEntryView(entry: entry)
                .widgetURL(AdalmonRoute.battery.url)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mac pili")
        .description("Büyük yüzde, kalan süre ve pil sağlığı.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct MacBatteryEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            MacBatteryWidgetView(snapshot: snapshot, size: family.adalmonSize ?? .small, now: entry.date)
        } else {
            WidgetNoDataView()
        }
    }
}

struct SystemWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.Kind.system, provider: SnapshotProvider()) { entry in
            SystemEntryView(entry: entry)
                .widgetURL(AdalmonRoute.system.url)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sistem")
        .description("CPU, RAM ve ağ hızı.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct SystemEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            SystemWidgetView(snapshot: snapshot, size: family.adalmonSize ?? .small, now: entry.date)
        } else {
            WidgetNoDataView()
        }
    }
}

struct MobileQuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.Kind.mobileQuota, provider: SnapshotProvider()) { entry in
            MobileQuotaEntryView(entry: entry)
                .widgetURL(AdalmonRoute.mobile.url)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mobil kota")
        .description("Günlük ve dönemlik mobil veri kullanımı.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct MobileQuotaEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            MobileQuotaWidgetView(snapshot: snapshot, size: family.adalmonSize ?? .small, now: entry.date)
        } else {
            WidgetNoDataView()
        }
    }
}
