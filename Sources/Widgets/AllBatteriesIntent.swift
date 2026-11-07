import AppIntents
import WidgetKit

enum DeviceSelectionOption: String, AppEnum {
    case automatic, custom, sameAsMenuBar

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Cihazlar")
    static let caseDisplayRepresentations: [DeviceSelectionOption: DisplayRepresentation] = [
        .automatic: "Otomatik (sığdığı kadar)",
        .custom: "Özel (kendi sıram)",
        .sameAsMenuBar: "Menü çubuğuyla aynı",
    ]

    var model: WidgetDeviceSelection {
        switch self {
        case .automatic: .automatic
        case .custom: .custom
        case .sameAsMenuBar: .sameAsMenuBar
        }
    }
}

enum BatteryStyleOption: String, AppEnum {
    case rings, list, bars

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Stil")
    static let caseDisplayRepresentations: [BatteryStyleOption: DisplayRepresentation] = [
        .rings: "Halkalar", .list: "Liste", .bars: "Çubuklar",
    ]

    var model: WidgetBatteryStyle {
        switch self {
        case .rings: .rings
        case .list: .list
        case .bars: .bars
        }
    }
}

enum AppearanceOption: String, AppEnum {
    case color, mono

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Görünüm")
    static let caseDisplayRepresentations: [AppearanceOption: DisplayRepresentation] = [
        .color: "Renkli", .mono: "Tek renk",
    ]
}

/// Özel cihaz seçimi için aksesuar varlığı; liste widget'ın okuduğu anlık görüntüden gelir.
struct BatteryDeviceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Cihaz")
    static let defaultQuery = BatteryDeviceQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct BatteryDeviceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BatteryDeviceEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BatteryDeviceEntity] { all() }

    private func all() -> [BatteryDeviceEntity] {
        (WidgetSnapshotStore.read()?.devices ?? []).map { BatteryDeviceEntity(id: $0.id, name: $0.name) }
    }
}

struct AllBatteriesIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Tüm piller"
    static let description = IntentDescription("Hangi pillerin, hangi stilde gösterileceğini seç.")

    @Parameter(title: "Cihazlar", default: .automatic)
    var selection: DeviceSelectionOption

    @Parameter(title: "Seçili cihazlar")
    var devices: [BatteryDeviceEntity]?

    @Parameter(title: "Stil", default: .rings)
    var style: BatteryStyleOption

    @Parameter(title: "Cihaz adlarını göster", default: true)
    var showNames: Bool

    @Parameter(title: "Bu Mac'i ekle", default: true)
    var includeMac: Bool

    @Parameter(title: "Görünüm", default: .color)
    var appearance: AppearanceOption

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$selection
            \.$devices
            \.$style
            \.$showNames
            \.$includeMac
            \.$appearance
        }
    }

    var options: WidgetBatteryOptions {
        WidgetBatteryOptions(selection: selection.model, customIDs: (devices ?? []).map(\.id), style: style.model,
                             showNames: showNames, includeMac: includeMac, appearance: appearance == .color ? .color : .mono)
    }
}

struct AllBatteriesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample()) }

    func snapshot(for configuration: AllBatteriesIntent, in context: Context) async -> SnapshotEntry {
        let snap = context.isPreview ? WidgetSnapshot.sample() : WidgetSnapshotStore.read() ?? .sample()
        return SnapshotEntry(date: .now, snapshot: snap, options: configuration.options)
    }

    func timeline(for configuration: AllBatteriesIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        SnapshotTimelineBuilder.timeline(options: configuration.options)
    }
}
