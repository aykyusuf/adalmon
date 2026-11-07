import AppKit
import SwiftUI

/// Önizlemede seçilebilen widget türleri.
enum WidgetPreviewKind: String, CaseIterable, Identifiable {
    case allBatteries, macBattery, system, mobileQuota

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allBatteries: "Tüm piller"
        case .macBattery: "Mac pili"
        case .system: "Sistem"
        case .mobileQuota: "Mobil kota"
        }
    }

    var symbol: String {
        switch self {
        case .allBatteries: "square.grid.2x2"
        case .macBattery: "laptopcomputer"
        case .system: "cpu"
        case .mobileQuota: "antenna.radiowaves.left.and.right"
        }
    }

    var summary: String {
        switch self {
        case .allBatteries: "Mac'in ve tüm aksesuarların tek pencere öğesinde. Boyut büyüdükçe daha çok cihaz sığar."
        case .macBattery: "Büyük yüzde, kalan ya da dolum süresi ve pil sağlığı. Büyük boyutta aksesuarlar da görünür."
        case .system: "CPU, RAM ve ağ indirme/yükleme hızı küçük kartlarda. Büyük boyutta mobil kota da eklenir."
        case .mobileQuota: "Günlük (ve ayarlıysa dönemlik) mobil veri kullanımı, kalan miktar ve limit göstergesi."
        }
    }

    /// Sağ tık → Pencere Öğesini Düzenle'de neler değişir.
    var options: [(symbol: String, text: String)] {
        switch self {
        case .allBatteries: [
            ("list.bullet.indent", "**Cihazlar:** Otomatik (sığdığı kadar), Özel (kendi sıran) ya da Menü çubuğuyla aynı"),
            ("square.grid.2x2", "**Stil:** Halkalar, Liste ya da Çubuklar"),
            ("switch.2", "**Cihaz adlarını göster** · **Bu Mac'i ekle**"),
            ("paintpalette", "**Görünüm:** Renkli ya da Tek renk"),
        ]
        default: [("hand.tap", "Dokununca Adalmon ilgili sayfada açılır. Bu pencere öğesinin ayarı yoktur.")]
        }
    }

    var route: AdalmonRoute {
        switch self {
        case .allBatteries, .macBattery: .battery
        case .system: .system
        case .mobileQuota: .mobile
        }
    }
}

/// Seçili tür/boyut/stil için widget'ın uygulama içi önizlemesi (gerçek widget ile aynı görünüm).
struct WidgetPreviewContent: View {
    var kind: WidgetPreviewKind
    var size: WidgetSize
    var snapshot: WidgetSnapshot
    var options: WidgetBatteryOptions
    var now: Date = .now

    var body: some View {
        WidgetPreviewFrame(size: size) {
            switch kind {
            case .allBatteries: AllBatteriesWidgetView(snapshot: snapshot, options: options, size: size, now: now)
            case .macBattery: MacBatteryWidgetView(snapshot: snapshot, size: size, appearance: options.appearance, now: now)
            case .system: SystemWidgetView(snapshot: snapshot, size: size, appearance: options.appearance, now: now)
            case .mobileQuota: MobileQuotaWidgetView(snapshot: snapshot, size: size, appearance: options.appearance, now: now)
            }
        }
    }
}

struct WidgetsSettingsPane: View {
    let snapshot: () -> WidgetSnapshot
    let isLive: () -> Bool

    @State private var kind: WidgetPreviewKind = .allBatteries
    @State private var size: WidgetSize = .small
    @State private var options = WidgetBatteryOptions()

    init(model: AppModel) {
        snapshot = { model.widgetSnapshot() }
        isLive = { model.battery.hasBattery || !model.devices.devices.isEmpty }
    }

    init(snapshot: @escaping () -> WidgetSnapshot, isLive: @escaping () -> Bool = { false },
         kind: WidgetPreviewKind = .allBatteries, size: WidgetSize = .small) {
        self.snapshot = snapshot
        self.isLive = isLive
        _kind = State(initialValue: kind)
        _size = State(initialValue: size)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Pilini ve sistem bilgisini masaüstüne ve Bildirim Merkezi'ne koy.")
                    .foregroundStyle(.secondary)
                typesCard
                addCard
                knowCard
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Bölümler

    private var typesCard: some View {
        WidgetsSection(title: "Pencere öğesi türleri", symbol: "square.grid.2x2.fill", accessory: {
            HStack(spacing: 5) {
                Circle().fill(isLive() ? Color.green : Color.gray).frame(width: 7, height: 7)
                Text(isLive() ? "Canlı önizleme" : "Örnek veri").font(.caption).foregroundStyle(.secondary)
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(WidgetPreviewKind.allCases) { k in
                        Chip(title: k.title, symbol: k.symbol, selected: kind == k) { kind = k }
                    }
                }
                HStack(spacing: 6) {
                    ForEach(WidgetSize.allCases) { s in Chip(title: s.title, symbol: nil, selected: size == s, compact: true) { size = s } }
                    Spacer(minLength: 0)
                    if kind == .allBatteries {
                        Picker("Stil", selection: $options.style) {
                            ForEach(WidgetBatteryStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                }
                HStack {
                    Spacer()
                    WidgetPreviewContent(kind: kind, size: size, snapshot: snapshot(), options: options)
                    Spacer()
                }
                .padding(.vertical, 18)
                .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 14))
                if kind == .allBatteries {
                    HStack(spacing: 18) {
                        Toggle("Cihaz adlarını göster", isOn: $options.showNames)
                        Toggle("Bu Mac'i ekle", isOn: $options.includeMac)
                        Picker("Görünüm", selection: $options.appearance) {
                            ForEach(WidgetAppearance.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).fixedSize()
                    }
                    .controlSize(.small)
                } else {
                    Picker("Görünüm", selection: $options.appearance) {
                        ForEach(WidgetAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).fixedSize().controlSize(.small)
                }
                Divider()
                Text(kind.summary).font(.callout).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind == .allBatteries ? "Neleri değiştirebilirsin (pencere öğesine sağ tık → Pencere Öğesini Düzenle):" : "Dokunma:")
                        .font(.callout.weight(.semibold))
                    ForEach(kind.options, id: \.text) { option in
                        Label { Text(.init(option.text)).font(.callout) } icon: {
                            Image(systemName: option.symbol).foregroundStyle(.secondary).frame(width: 18)
                        }
                    }
                    Text("Dokununca Adalmon açılır (\(kind.route.url.absoluteString)).").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var addCard: some View {
        WidgetsSection(title: "Pencere öğesi ekle", symbol: "plus.square.on.square") {
            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "Masaüstüne sağ tıkla ve **Pencere Öğelerini Düzenle…**'yi seç; ya da Bildirim Merkezi'ni aç (saate tıkla) ve en alta kaydır.")
                Divider()
                StepRow(number: 2, text: "**Adalmon**'u ara ve bir pencere öğesini istediğin yere sürükle. Her boyut galeride ayrı bir seçenektir.")
                Divider()
                StepRow(number: 3, text: "Yerleştirdiğin pencere öğesine sağ tıkla → **Pencere Öğesini Düzenle**; cihazları, stili ve adları seç.")
            }
        }
    }

    private var knowCard: some View {
        WidgetsSection(title: "Bilmekte fayda var", symbol: "info.circle") {
            VStack(alignment: .leading, spacing: 12) {
                Note(symbol: "slider.horizontal.3", title: "Her pencere öğesinin kendi ayarı var",
                     text: "Aynı pencere öğesini farklı ayarlarla iki kez ekleyebilirsin (örneğin biri halkalar, biri liste).")
                Divider()
                Note(symbol: "menubar.rectangle", title: "Adalmon çalışırken güncel kalır",
                     text: "Adalmon'u menü çubuğunda açık tut (Genel › Girişte başlat). 15 dakikadan uzun süre veri gelmezse pencere öğesi \"\(WidgetFormat.staleText)\" yazar.")
                Divider()
                Note(symbol: "lock.shield", title: "Yalnızca küçük bir özet paylaşılır",
                     text: "Pil, CPU/RAM, ağ hızı ve mobil kota; uygulama grubu klasörüne dakikada en fazla bir kez yazılır. Uygulama adları ya da trafik ayrıntısı yazılmaz.")
            }
        }
    }
}

// MARK: Parçalar

struct WidgetsSection<Content: View, Accessory: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(title: String, symbol: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: symbol).font(.title3.weight(.semibold))
                Spacer()
                accessory
            }
            .accessibilityAddTraits(.isHeader)
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}

extension WidgetsSection where Accessory == EmptyView {
    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, accessory: { EmptyView() }, content: content)
    }
}

private struct Chip: View {
    let title: String
    let symbol: String?
    let selected: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12)) }
                Text(title).font(.system(size: compact ? 12 : 13, weight: selected ? .semibold : .regular))
            }
            .padding(.horizontal, compact ? 11 : 13).padding(.vertical, compact ? 4 : 6)
            .background(selected ? Color.primary.opacity(0.14) : Color.primary.opacity(0.05), in: .capsule)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0.2 : 0.06)))
            .foregroundStyle(selected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Color.teal.gradient, in: .circle)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Note: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ShortcutsSettingsPane: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Adalmon, Kestirmeler uygulamasına, Spotlight'a ve Siri'ye eylemler sunar. Kestirmeler uygulamasında “Adalmon” altında bulunur.")
                    .foregroundStyle(.secondary)
                WidgetsSection(title: "Kullanılabilir kestirmeler", symbol: "command") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(ShortcutCatalog.entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider().padding(.vertical, 9) }
                            HStack(alignment: .top, spacing: 12) {
                                SettingsSidebarIcon(symbol: entry.symbol, tint: .indigo)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title).font(.callout.weight(.semibold))
                                    Text(entry.detail).font(.callout).foregroundStyle(.secondary)
                                    if let phrase = entry.phrase {
                                        Text("Siri/Spotlight: “\(phrase)”").font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
                HStack {
                    Button("Kestirmeler'i aç", systemImage: "arrow.up.forward.app") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                        }
                    }
                    Text("Kestirmeler yalnızca Adalmon çalışırken yanıt verir.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}
