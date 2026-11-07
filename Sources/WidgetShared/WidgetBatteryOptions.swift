import Foundation

enum WidgetDeviceSelection: String, Codable, CaseIterable, Sendable { case automatic, custom, sameAsMenuBar }
enum WidgetBatteryStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case rings, list, bars
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rings: "Halkalar"
        case .list: "Liste"
        case .bars: "Çubuklar"
        }
    }
}
enum WidgetAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case color, mono
    var id: String { rawValue }
    var title: String { self == .color ? "Renkli" : "Tek renk" }
}

enum WidgetSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: "Küçük"
        case .medium: "Orta"
        case .large: "Büyük"
        }
    }
    /// macOS masaüstü widget boyutları (pt).
    var canvas: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        }
    }
}

/// Listede gösterilecek tek pil (Mac ya da aksesuar).
struct WidgetBatteryItem: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var symbol: String
    var level: Int?
    var isCharging: Bool
    var isApproximate: Bool
    var isConnected: Bool
    var isMac: Bool

    var levelText: String { level.map { (isApproximate ? "~" : "") + "%\($0)" } ?? "—" }
    var fraction: Double { Double(max(0, min(100, level ?? 0))) / 100 }
}

/// "Tüm piller" widget ayarları (App Intent'ten çözülmüş, saf veri).
struct WidgetBatteryOptions: Equatable, Sendable {
    var selection: WidgetDeviceSelection = .automatic
    var customIDs: [String] = []
    var style: WidgetBatteryStyle = .rings
    var showNames = true
    var includeMac = true
    var appearance: WidgetAppearance = .color

    /// Gösterilecek piller, sıralı. Taşma (kapasiteden fazla) çağıran tarafta kesilir.
    func items(from snapshot: WidgetSnapshot) -> [WidgetBatteryItem] {
        var result: [WidgetBatteryItem] = []
        if includeMac, let mac = snapshot.mac {
            result.append(WidgetBatteryItem(id: "__mac__", name: "Bu Mac", symbol: "laptopcomputer", level: mac.level,
                                            isCharging: mac.isCharging, isApproximate: false, isConnected: true, isMac: true))
        }
        let withLevel = snapshot.devices.filter { $0.level != nil }
        let chosen: [WidgetSnapshot.DeviceEntry]
        switch selection {
        case .automatic:
            // Bağlı olanlar önce; kendi içinde alfabetik değil, kaynak sırası korunur.
            chosen = withLevel.filter(\.isConnected) + withLevel.filter { !$0.isConnected }
        case .custom:
            chosen = customIDs.compactMap { id in withLevel.first { $0.id == id } }
        case .sameAsMenuBar:
            chosen = snapshot.pinnedDeviceIDs.compactMap { id in withLevel.first { $0.id == id } }
        }
        for d in chosen {
            result.append(WidgetBatteryItem(id: d.id, name: d.name, symbol: d.symbol, level: d.level, isCharging: d.isCharging,
                                            isApproximate: d.isApproximate, isConnected: d.isConnected, isMac: false))
        }
        return result
    }

    /// (sütun, satır) kapasitesi: boyut büyüdükçe daha çok cihaz sığar.
    static func grid(style: WidgetBatteryStyle, size: WidgetSize) -> (columns: Int, rows: Int) {
        switch (style, size) {
        case (.rings, .small): (2, 2)
        case (.rings, .medium): (4, 2)
        case (.rings, .large): (4, 3)
        case (.list, .small): (1, 4)
        case (.list, .medium): (2, 4)
        case (.list, .large): (1, 9)
        case (.bars, .small): (1, 4)
        case (.bars, .medium): (2, 4)
        case (.bars, .large): (1, 8)
        }
    }

    func capacity(for size: WidgetSize) -> Int {
        let g = Self.grid(style: style, size: size)
        return g.columns * g.rows
    }

    /// Boş durum ipucu.
    func emptyHint(snapshot: WidgetSnapshot) -> String {
        switch selection {
        case .sameAsMenuBar: "Menü çubuğuna sabitlenmiş cihaz yok"
        case .custom: "Seçili cihaz bulunamadı"
        case .automatic: snapshot.mac == nil && snapshot.devices.isEmpty ? "Henüz pil bilgisi yok" : "Gösterilecek pil yok"
        }
    }
}
