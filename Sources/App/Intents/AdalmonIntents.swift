import AppIntents
import Foundation

// MARK: Varlık ve numaralandırmalar

struct AppTargetEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Uygulama")
    static let defaultQuery = AppTargetQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct AppTargetQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [AppTargetEntity] {
        let backend = try AdalmonIntentHub.require()
        return identifiers.map { AppTargetEntity(id: $0, name: backend.appName(for: $0)) }
    }

    @MainActor func entities(matching string: String) async throws -> [AppTargetEntity] {
        try AdalmonIntentHub.require().knownApps()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map { AppTargetEntity(id: $0.id, name: $0.name) }
    }

    @MainActor func suggestedEntities() async throws -> [AppTargetEntity] {
        try AdalmonIntentHub.require().knownApps().map { AppTargetEntity(id: $0.id, name: $0.name) }
    }
}

enum AdalmonPage: String, AppEnum {
    case overview, battery, mobile, network, history, rules, processes, widgets, shortcuts

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sayfa")
    static let caseDisplayRepresentations: [AdalmonPage: DisplayRepresentation] = [
        .overview: "Genel bakış", .battery: "Pil", .mobile: "Mobil veri", .network: "Ağ kullanımı", .history: "Geçmiş",
        .rules: "Kurallar", .processes: "Süreçler", .widgets: "Widget'lar", .shortcuts: "Kestirmeler",
    ]

    var route: AdalmonRoute {
        switch self {
        case .overview: .overview
        case .battery: .battery
        case .mobile: .mobile
        case .network: .network
        case .history: .history
        case .rules: .rules
        case .processes: .processes
        case .widgets: .widgets
        case .shortcuts: .shortcuts
        }
    }
}

// MARK: Okuma kestirmeleri

struct GetBatteryStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Pil durumunu al"
    static let description = IntentDescription("Mac'in pil yüzdesini, durumunu ve kalan/dolum süresini verir.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let answer = try AdalmonIntentHub.require().batteryStatus() else { throw AdalmonIntentError.noBattery }
        let text = IntentMapping.batteryText(answer)
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct GetDeviceBatteriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Cihaz pillerini al"
    static let description = IntentDescription("iPhone, AirPods, klavye, fare gibi cihazların pil yüzdelerini verir.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = IntentMapping.devicesText(try AdalmonIntentHub.require().deviceBatteries())
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct GetMobileUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Mobil veri kullanımını al"
    static let description = IntentDescription("Bugünkü ve (ayarlıysa) dönemlik mobil veri kullanımını verir.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = IntentMapping.mobileText(try AdalmonIntentHub.require().mobileUsage())
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

// MARK: Eylem kestirmeleri

struct OpenAdalmonIntent: AppIntent {
    static let title: LocalizedStringResource = "Adalmon'u aç"
    static let description = IntentDescription("Adalmon'u seçtiğin sayfada açar. Dock modu kapalıysa en yakın ayar bölümü açılır.")

    @Parameter(title: "Sayfa", default: .overview)
    var page: AdalmonPage

    init() {}
    init(page: AdalmonPage) { self.page = page }

    static var parameterSummary: some ParameterSummary { Summary("Adalmon'u \(\.$page) sayfasında aç") }

    @MainActor func perform() async throws -> some IntentResult {
        try AdalmonIntentHub.require().open(route: page.route)
        return .result()
    }
}

struct SetThrottleIntent: AppIntent {
    static let title: LocalizedStringResource = "Hız sınırı koy"
    static let description = IntentDescription("Bir uygulamanın indirme ve yükleme hızını KB/sn olarak sınırlar (ağ filtresi gerekir).")

    @Parameter(title: "Uygulama")
    var app: AppTargetEntity

    @Parameter(title: "Sınır (KB/sn)", default: 500, inclusiveRange: (1, 1_000_000))
    var kilobytesPerSecond: Int

    @Parameter(title: "Yalnızca mobil veride", default: false)
    var onlyOnMobile: Bool

    init() {}
    init(app: AppTargetEntity, kilobytesPerSecond: Int, onlyOnMobile: Bool = false) {
        self.app = app
        self.kilobytesPerSecond = kilobytesPerSecond
        self.onlyOnMobile = onlyOnMobile
    }

    static var parameterSummary: some ParameterSummary { Summary("\(\.$app) için hız sınırı \(\.$kilobytesPerSecond) KB/sn") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let limit = IntentMapping.limit(kilobytesPerSecond: kilobytesPerSecond, onlyOnMobile: onlyOnMobile) else {
            throw AdalmonIntentError.invalidSpeed
        }
        try AdalmonIntentHub.require().setThrottle(appID: app.id, limit: limit)
        return .result(dialog: IntentDialog(stringLiteral: "\(app.name) için hız sınırı \(kilobytesPerSecond) KB/sn."))
    }
}

struct RemoveThrottleIntent: AppIntent {
    static let title: LocalizedStringResource = "Hız sınırını kaldır"
    static let description = IntentDescription("Bir uygulamadaki hız sınırını kaldırır.")

    @Parameter(title: "Uygulama")
    var app: AppTargetEntity

    init() {}
    init(app: AppTargetEntity) { self.app = app }

    static var parameterSummary: some ParameterSummary { Summary("\(\.$app) hız sınırını kaldır") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try AdalmonIntentHub.require().removeThrottle(appID: app.id)
        return .result(dialog: IntentDialog(stringLiteral: "\(app.name) hız sınırı kaldırıldı."))
    }
}

struct SetBlockedOnMobileIntent: AppIntent {
    static let title: LocalizedStringResource = "Mobilde engelle / kaldır"
    static let description = IntentDescription("Bir uygulamayı mobil veride engeller ya da engelini kaldırır (ağ filtresi gerekir).")

    @Parameter(title: "Uygulama")
    var app: AppTargetEntity

    @Parameter(title: "Engelle", default: true)
    var blocked: Bool

    init() {}
    init(app: AppTargetEntity, blocked: Bool) {
        self.app = app
        self.blocked = blocked
    }

    static var parameterSummary: some ParameterSummary { Summary("\(\.$app) mobilde engellensin: \(\.$blocked)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try AdalmonIntentHub.require().setBlockedOnMobile(appID: app.id, blocked: blocked)
        return .result(dialog: IntentDialog(stringLiteral: blocked ? "\(app.name) mobilde engellendi." : "\(app.name) engeli kaldırıldı."))
    }
}

// MARK: Kestirme sağlayıcı

struct AdalmonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetBatteryStatusIntent(),
                    phrases: ["\(.applicationName) pil durumu", "\(.applicationName) ile pil durumunu al", "\(.applicationName) pilim kaç"],
                    shortTitle: "Pil durumu", systemImageName: "battery.100percent")
        AppShortcut(intent: GetDeviceBatteriesIntent(),
                    phrases: ["\(.applicationName) cihaz pilleri", "\(.applicationName) ile cihaz pillerini al"],
                    shortTitle: "Cihaz pilleri", systemImageName: "airpodspro")
        AppShortcut(intent: GetMobileUsageIntent(),
                    phrases: ["\(.applicationName) mobil veri kullanımı", "\(.applicationName) ile mobil veriyi al"],
                    shortTitle: "Mobil veri", systemImageName: "antenna.radiowaves.left.and.right")
        AppShortcut(intent: OpenAdalmonIntent(),
                    phrases: ["\(.applicationName) uygulamasını aç", "\(.applicationName) ile sayfa aç"],
                    shortTitle: "Adalmon'u aç", systemImageName: "arrow.up.forward.app")
        AppShortcut(intent: SetThrottleIntent(),
                    phrases: ["\(.applicationName) hız sınırı koy"],
                    shortTitle: "Hız sınırı koy", systemImageName: "speedometer")
        AppShortcut(intent: SetBlockedOnMobileIntent(),
                    phrases: ["\(.applicationName) mobilde engelle"],
                    shortTitle: "Mobilde engelle", systemImageName: "nosign")
    }
}

/// Ayarlar › Kestirmeler listesi (UI ve testler aynı katalogdan okur).
struct ShortcutCatalogEntry: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var phrase: String?
    var symbol: String
}

enum ShortcutCatalog {
    static let entries: [ShortcutCatalogEntry] = [
        .init(id: "battery", title: "Pil durumunu al", detail: "Mac'in yüzdesi, durumu ve kalan/dolum süresi.", phrase: "Adalmon pil durumu", symbol: "battery.100percent"),
        .init(id: "devices", title: "Cihaz pillerini al", detail: "iPhone, AirPods, klavye, fare pilleri.", phrase: "Adalmon cihaz pilleri", symbol: "airpodspro"),
        .init(id: "mobile", title: "Mobil veri kullanımını al", detail: "Bugünkü ve dönemlik mobil veri.", phrase: "Adalmon mobil veri kullanımı", symbol: "antenna.radiowaves.left.and.right"),
        .init(id: "open", title: "Adalmon'u aç (sayfa)", detail: "Seçtiğin sayfada açar.", phrase: "Adalmon uygulamasını aç", symbol: "arrow.up.forward.app"),
        .init(id: "throttle", title: "Hız sınırı koy", detail: "Uygulama + KB/sn; isteğe bağlı yalnızca mobilde.", phrase: "Adalmon hız sınırı koy", symbol: "speedometer"),
        .init(id: "unthrottle", title: "Hız sınırını kaldır", detail: "Seçtiğin uygulamanın sınırını kaldırır.", phrase: nil, symbol: "speedometer"),
        .init(id: "block", title: "Mobilde engelle / kaldır", detail: "Uygulamayı mobil veride engeller ya da engelini kaldırır.", phrase: "Adalmon mobilde engelle", symbol: "nosign"),
    ]
}
