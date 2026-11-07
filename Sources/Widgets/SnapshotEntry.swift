import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var options = WidgetBatteryOptions()
}

extension WidgetFamily {
    /// Sistem ailesi → ortak boyut; aksesuar aileleri `nil`.
    var adalmonSize: WidgetSize? {
        switch self {
        case .systemSmall: .small
        case .systemMedium: .medium
        case .systemLarge, .systemExtraLarge: .large
        default: nil
        }
    }
}

enum SnapshotTimelineBuilder {
    static func timeline(options: WidgetBatteryOptions = WidgetBatteryOptions(), now: Date = .now) -> Timeline<SnapshotEntry> {
        let snapshot = WidgetSnapshotStore.read()
        let plan = WidgetTimelinePlan.make(snapshotDate: snapshot?.generatedAt, now: now)
        let entries = plan.dates.map { SnapshotEntry(date: $0, snapshot: snapshot, options: options) }
        return Timeline(entries: entries, policy: .after(plan.refreshAt))
    }
}

/// Ayarsız (statik) widget'lar için sağlayıcı.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample()) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snap = context.isPreview ? WidgetSnapshot.sample() : WidgetSnapshotStore.read() ?? .sample()
        completion(SnapshotEntry(date: .now, snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(SnapshotTimelineBuilder.timeline())
    }
}
