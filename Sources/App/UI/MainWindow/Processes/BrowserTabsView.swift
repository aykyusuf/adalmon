import AppKit
import SwiftUI

/// "Tarayıcılar": Chrome tarzı sekme şeridiyle Safari ve Chrome. Safari: sekme listesi (AppleScript, opt-in) + Web İçeriği RAM'i (tahmini);
/// Chrome: gelişmiş hata ayıklama modu (sekme başına JS belleği). Yoklama yalnızca bu sekme görünürken ve pencere öndeyken çalışır.
/// Safari de Chrome de "hangi süreç hangi sekme" bilgisini vermez; arayüz bunu tahmin gibi göstermez, ayrı ayrı ve açıkça listeler.
struct BrowserTabsView: View {
    let model: AppModel
    @State private var browser: BrowserTabsModel
    @AppStorage("browserTabs.selectedBrowser") private var selectedRaw = BrowserKind.safari.rawValue

    /// `browser`: önizleme/test için hazır model verilebilir (varsayılan: gerçek model).
    init(model: AppModel, browser: BrowserTabsModel = BrowserTabsModel()) {
        self.model = model
        _browser = State(initialValue: browser)
    }

    private var selected: BrowserKind { BrowserKind(rawValue: selectedRaw) ?? .safari }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrowserTabStrip(selected: Binding(get: { selected }, set: { selectedRaw = $0.rawValue }),
                            safariCount: browser.safariEnabled && browser.safariState == .loaded ? browser.safariTabs.count : nil,
                            chromeCount: browser.chromeEnabled && browser.chromeState == .connected ? browser.chromeTabs.count : nil)
            ScrollView {
                Group {
                    switch selected {
                    case .safari: SafariPanel(browser: browser)
                    case .chrome: ChromePanel(browser: browser)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .task(id: browser.safariEnabled) {
            guard browser.safariEnabled else { return }
            await browser.runSafari { [model] in model.mainWindowVisible && NSApp.isActive }
        }
        .task(id: browser.chromeEnabled) {
            guard browser.chromeEnabled else { return }
            await browser.runChrome { [model] in model.mainWindowVisible && NSApp.isActive }
        }
    }
}

enum BrowserKind: String, CaseIterable, Identifiable {
    case safari, chrome
    var id: String { rawValue }
    var title: String { self == .safari ? "Safari" : "Chrome" }
    var symbol: String { self == .safari ? "safari" : "globe" }
}

// MARK: Sekme şeridi

private struct BrowserTabStrip: View {
    @Binding var selected: BrowserKind
    let safariCount: Int?
    let chromeCount: Int?
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 4) {
            ForEach(BrowserKind.allCases) { kind in
                let count = kind == .safari ? safariCount : chromeCount
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selected = kind }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: kind.symbol).font(.callout.weight(.semibold))
                        Text(kind.title).font(.callout.weight(.semibold))
                        if let count {
                            Text("\(count)").font(.caption2.weight(.bold)).monospacedDigit()
                                .padding(.horizontal, 6).padding(.vertical, 1.5)
                                .background(.quaternary, in: .capsule)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .foregroundStyle(selected == kind ? Color.primary : Color.secondary)
                    .background {
                        if selected == kind {
                            RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.18))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.45)))
                                .matchedGeometryEffect(id: "tab", in: highlight)
                        }
                    }
                    .contentShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.title + (count.map { ", \($0) sekme" } ?? ""))
                .accessibilityAddTraits(selected == kind ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 14))
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: Safari

private struct SafariPanel: View {
    @Bindable var browser: BrowserTabsModel
    @State private var query = ""
    private static let maxTabs = 80
    private static let maxProcesses = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ResourceCard(title: "Safari", systemImage: "safari") {
                HStack(spacing: 10) {
                    Toggle("Sekme listesini göster", isOn: $browser.safariEnabled).toggleStyle(.switch)
                    Spacer(minLength: 8)
                    if browser.safariEnabled, browser.safariState == .loaded, let updated = browser.safariUpdated {
                        TimelineView(.periodic(from: .now, by: 5)) { ctx in
                            Label("\(max(0, Int(ctx.date.timeIntervalSince(updated)))) sn önce", systemImage: "arrow.clockwise")
                                .font(.caption).foregroundStyle(.tertiary).labelStyle(.titleAndIcon)
                        }
                    }
                }
                if !browser.safariEnabled {
                    BrowserEmptyHint(symbol: "safari", title: "Safari sekmeleri kapalı",
                                     text: "Açınca Adalmon, Safari'deki açık sekmelerin başlık ve adreslerini AppleScript ile okur. İlk seferde macOS “Adalmon, Safari'yi denetlemek istiyor” diye izin sorar. Kapalıyken Safari'ye hiçbir istek gönderilmez.")
                } else {
                    stateContent
                }
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch browser.safariState {
        case .off, .checking:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Safari denetleniyor…").foregroundStyle(.secondary) }
        case .notRunning:
            BrowserEmptyHint(symbol: "moon.zzz", title: "Safari açık değil",
                             text: "Safari açılınca sekmeler burada görünür (Adalmon Safari'yi kendisi başlatmaz).")
        case .needsPermission:
            VStack(alignment: .leading, spacing: 10) {
                BrowserEmptyHint(symbol: "hand.raised", title: "Otomasyon izni gerekiyor",
                                 text: "Düğmeye basınca macOS bir izin penceresi gösterir; “İzin Ver”i seçin. Adalmon yalnızca sekme başlık ve adreslerini okur, Safari'de hiçbir şeyi değiştirmez.")
                Button("İzin ver ve sekmeleri oku", systemImage: "hand.raised") { Task { await browser.requestSafariPermission() } }
            }
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Label(SafariTabsError.permissionDenied.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                Button("Otomasyon ayarlarını aç", systemImage: "gear") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        case .loaded:
            loaded
        }
    }

    @ViewBuilder
    private var loaded: some View {
        let tabs = browser.safariTabs
        let windows = Set(tabs.map(\.window)).count
        let memory = browser.safariMemory
        HStack(alignment: .top, spacing: 10) {
            BrowserStatTile(symbol: "square.on.square", title: "Sekme", value: "\(tabs.count)", detail: windows == 1 ? "1 pencere" : "\(windows) pencere")
            if let memory {
                BrowserStatTile(symbol: "memorychip", title: "Web İçeriği toplamı", value: ResourceFormat.bytes(Double(memory.total)),
                                detail: "\(memory.processes.count) süreç", tint: BrowserHeat.tint(bytes: memory.total, scale: 4))
                if let average = memory.averagePerTab {
                    BrowserStatTile(symbol: "divide.circle", title: "Sekme başına ≈", value: ResourceFormat.bytes(Double(average)), detail: "tahmini ortalama",
                                    tint: BrowserHeat.tint(bytes: average))
                }
            }
            Spacer(minLength: 0)
        }
        TabProbeBar(state: browser.safariProbe, mappedAt: browser.safariMap.updatedAt, safari: true,
                    hasTabs: !tabs.isEmpty) { Task { await browser.probeSafari() } }
        SiteChips(tabs: tabs.map { ($0.url) }, query: $query)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 22) { tabList.frame(minWidth: 340, idealWidth: 480, maxWidth: .infinity); processList.frame(minWidth: 300, idealWidth: 360, maxWidth: 460) }
            VStack(alignment: .leading, spacing: 18) { tabList; processList }
        }
    }

    /// Bu sürece eşlenen sekme başlıkları (ölçüm yapıldıysa).
    private func mappedTitles(pid: Int32) -> [String] {
        browser.safariTabs.filter { browser.safariMap.pidByTab[BrowserTabsModel.safariKey(for: $0)] == pid }
            .map { $0.title.isEmpty ? BrowserTabRow.host($0.url) : $0.title }
    }

    private var filteredTabs: [SafariTab] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return browser.safariTabs }
        return browser.safariTabs.filter { $0.title.localizedStandardContains(needle) || $0.url.localizedStandardContains(needle) }
    }

    private var tabList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Açık sekmeler").font(.subheadline.weight(.semibold))
                Spacer(minLength: 6)
                BrowserSearchField(text: $query, prompt: "Sekme ara")
            }
            let tabs = filteredTabs
            if tabs.isEmpty { Text(query.isEmpty ? "Açık sekme yok." : "Eşleşen sekme yok.").font(.callout).foregroundStyle(.secondary) }
            let multiWindow = Set(browser.safariTabs.map(\.window)).count > 1
            VStack(spacing: 2) {
                ForEach(tabs.prefix(Self.maxTabs)) { tab in
                    let pid = browser.safariMap.pidByTab[BrowserTabsModel.safariKey(for: tab)]
                    BrowserTabRow(title: tab.title, url: tab.url, badge: multiWindow ? "Pencere \(tab.window)" : nil, trailing: nil,
                                  memory: pid.flatMap { p in browser.safariMemory?.processes.first { $0.pid == p }?.footprint },
                                  shared: pid.map { browser.safariMap.sharedCount(for: $0) } ?? 0)
                }
            }
            if tabs.count > Self.maxTabs { Text("ve \(tabs.count - Self.maxTabs) sekme daha").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var processList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Web İçeriği süreçleri").font(.subheadline.weight(.semibold))
                Spacer(minLength: 6)
                BrowserInfoButton(text: "Safari sekme–süreç eşlemesini vermiyor: bir sürecin hangi sekmeye ait olduğu bilinmez, sıralama yalnızca RAM'edir. Ortalama = Web İçeriği toplamı ÷ tüm sekmeler (Safari arka plandaki sekmeleri boşaltabildiği için yüklü sekme sayısı bilinmiyor). Aynı süreçler Süreçler listesinde Safari satırının altında da görünür.")
            }
            let processes = browser.safariMemory?.processes ?? []
            if processes.isEmpty { Text("Safari Web İçeriği süreci bulunamadı.").font(.callout).foregroundStyle(.secondary) }
            let peak = Double(max(1, processes.first?.footprint ?? 1))
            let total = Double(max(1, browser.safariMemory?.total ?? 1))
            VStack(spacing: 2) {
                ForEach(Array(processes.prefix(Self.maxProcesses).enumerated()), id: \.element.id) { index, process in
                    BrowserMemoryRow(title: "Web İçeriği #\(index + 1)", detail: "pid \(process.pid) · %\(Int((Double(process.footprint) / total * 100).rounded()))",
                                     bytes: process.footprint, fraction: Double(process.footprint) / peak, tabs: mappedTitles(pid: process.pid))
                }
            }
            if processes.count > Self.maxProcesses { Text("ve \(processes.count - Self.maxProcesses) süreç daha").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

// MARK: Chrome

private struct ChromePanel: View {
    @Bindable var browser: BrowserTabsModel

    var body: some View {
        ResourceCard(title: "Chrome", systemImage: "globe") {
            HStack(spacing: 10) {
                Toggle("Gelişmiş modu etkinleştir", isOn: $browser.chromeEnabled).toggleStyle(.switch)
                Spacer(minLength: 8)
                BrowserInfoButton(text: "Chrome, sekmelerin süreç bilgisini normal profilde vermez. Bu mod, Chrome'un ayrı bir kopyasını Adalmon'a ait boş bir profille ve yalnızca bu Mac'e (127.0.0.1) açık bir hata ayıklama portuyla başlatır; açık olan Chrome'unuz kapatılmaz.")
            }
            Label("Yerel porta erişen her uygulama bu Chrome'u kontrol edebilir; ayrı profil kullanılır, oturumların taşınmaz. Bu pencerede hassas hesaplara giriş yapmayın.",
                  systemImage: "exclamationmark.shield.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            if browser.chromeEnabled { content }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch browser.chromeState {
        case .off, .idle:
            launchButton
        case .notInstalled:
            Text("Google Chrome bulunamadı.").font(.callout).foregroundStyle(.secondary)
        case .launching:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Chrome başlatılıyor ve bağlanılıyor…").foregroundStyle(.secondary) }
        case .disconnected(let message), .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            HStack {
                launchButton
                Button("Sıfırla") { browser.resetChromeConnection() }
            }
        case .connected:
            connected
        }
    }

    private var launchButton: some View {
        Button("Adalmon hata ayıklama profiliyle Chrome'u başlat", systemImage: "play.circle") {
            Task { await browser.launchChrome() }
        }
    }

    @ViewBuilder
    private var connected: some View {
        let tabs = browser.chromeTabs
        HStack(alignment: .top, spacing: 10) {
            BrowserStatTile(symbol: "square.on.square", title: "Sekme", value: "\(tabs.count)", detail: "hata ayıklama Chrome'u")
            if let renderer = browser.chromeRenderer, renderer.count > 0 {
                BrowserStatTile(symbol: "memorychip", title: "Renderer toplamı", value: ResourceFormat.bytes(Double(renderer.total)),
                                detail: "\(renderer.count) süreç", tint: BrowserHeat.tint(bytes: renderer.total, scale: 4))
            }
            Spacer(minLength: 0)
        }
        TabProbeBar(state: browser.chromeProbe, mappedAt: browser.chromeMap.updatedAt, safari: false,
                    hasTabs: !tabs.isEmpty) { Task { await browser.probeChrome() } }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Sekmeler").font(.subheadline.weight(.semibold))
                Text("JS belleği").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 6)
                BrowserInfoButton(text: "JS belleği yalnızca sayfanın JavaScript yığınıdır (kullanılan / ayrılan) ve DOM düğüm sayısıdır; sekmenin süreç RAM'i değildir. Chrome kararlı protokolde sekme–süreç eşlemesini vermez. Toplam renderer RAM'i \(browser.chromeRenderer == nil ? "için Süreçler listesindeki Google Chrome satırına bakın" : "bu Chrome'un renderer süreçlerinin toplamıdır").")
            }
            if tabs.isEmpty { Text("Açık sekme yok.").font(.callout).foregroundStyle(.secondary) }
            let peak = max(1, tabs.compactMap { $0.metrics?.jsHeapUsed }.max() ?? 1)
            VStack(spacing: 2) {
                ForEach(tabs) { tab in
                    let pid = browser.chromeMap.pidByTab[tab.id]
                    BrowserTabRow(title: tab.title, url: tab.url, badge: nil, trailing: Self.metricsText(tab.metrics),
                                  bar: tab.metrics?.jsHeapUsed.map { $0 / peak },
                                  memory: pid.flatMap { browser.chromeRenderer?.perPID[$0] },
                                  shared: pid.map { browser.chromeMap.sharedCount(for: $0) } ?? 0)
                }
            }
        }
    }

    private static func metricsText(_ m: CDPTabMetrics?) -> String {
        guard let m else { return "—" }
        var parts: [String] = []
        if let used = m.jsHeapUsed {
            let total = m.jsHeapTotal.map { " / \(ResourceFormat.bytes($0))" } ?? ""
            parts.append("JS \(ResourceFormat.bytes(used))\(total)")
        }
        if let nodes = m.nodes { parts.append("\(Int(nodes)) düğüm") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

// MARK: Ortak parçalar

/// RAM büyüklüğüne göre renk (yeşil → turuncu → kırmızı). `scale`: toplamlar için eşik çarpanı.
enum BrowserHeat {
    static func tint(bytes: UInt64, scale: Double = 1) -> Color {
        let mb = Double(bytes) / 1_048_576 / scale
        if mb >= 800 { return .red }
        if mb >= 400 { return .orange }
        return .green
    }
}

private struct BrowserStatTile: View {
    let symbol: String
    let title: String
    let value: String
    let detail: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.callout.weight(.semibold)).foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                Text(detail).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// Site rozetleri: açık sekmelerin en kalabalık siteleri (tıklayınca sekme aramasını o siteye daraltır).
private struct SiteChips: View {
    let tabs: [String]
    @Binding var query: String

    var body: some View {
        let counts = Dictionary(grouping: tabs.map { BrowserTabRow.host($0) }.filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        let top = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(8)
        if top.count > 1 || (top.first?.value ?? 0) > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(top), id: \.key) { host, count in
                        Button {
                            query = query == host ? "" : host
                        } label: {
                            HStack(spacing: 5) {
                                SiteAvatar(host: host, size: 16)
                                Text(host).font(.caption).lineLimit(1)
                                if count > 1 { Text("×\(count)").font(.caption2.weight(.bold)).foregroundStyle(.secondary) }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(query == host ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(host), \(count) sekme")
                        .accessibilityHint("Sekme listesini bu siteye göre süzer")
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

/// Sitenin ilk harfi, ana bilgisayar adından türeyen sabit renkte yuvarlak köşeli kare.
private struct SiteAvatar: View {
    let host: String
    var size: CGFloat = 26

    var body: some View {
        let hue = Double(host.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value } % 360) / 360
        Text(String(host.first.map { Character($0.uppercased()) } ?? "·"))
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hue: hue, saturation: 0.5, brightness: 0.72), in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

private struct BrowserTabRow: View {
    let title: String
    let url: String
    let badge: String?
    let trailing: String?
    var bar: Double?
    /// Eşleme yapıldıysa sekmenin süreç RAM'i; süreç birden çok sekme tarafından paylaşılıyorsa `shared` > 1 ("ortak").
    var memory: UInt64?
    var shared = 0
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            SiteAvatar(host: Self.host(url))
            VStack(alignment: .leading, spacing: 1) {
                Text(title.isEmpty ? "Adsız sekme" : title).font(.callout).lineLimit(1).truncationMode(.tail)
                Text(Self.host(url).isEmpty ? url : Self.host(url)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if let memory {
                HStack(spacing: 5) {
                    if shared > 1 {
                        Text("ortak ×\(shared)").font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(.quaternary, in: .capsule)
                            .help("Bu süreç \(shared) sekme tarafından paylaşılıyor; RAM ortaktır")
                    }
                    Text(ResourceFormat.bytes(Double(memory))).font(.callout.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(BrowserHeat.tint(bytes: memory))
                }
            }
            if let badge { Text(badge).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 1.5).background(.quaternary, in: .capsule) }
            if let bar {
                Capsule().fill(Color.accentColor.opacity(0.6)).frame(width: max(3, 56 * bar), height: 5)
            }
            if let trailing { Text(trailing).font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 9))
        .contentShape(.rect(cornerRadius: 9))
        .onHover { hovering = $0 }
        .help(url)
        .accessibilityElement(children: .combine)
    }

    static func host(_ url: String) -> String {
        guard let h = URL(string: url)?.host() else { return "" }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
}

private struct BrowserMemoryRow: View {
    let title: String
    let detail: String
    let bytes: UInt64
    let fraction: Double
    var tabs: [String] = []

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                if !tabs.isEmpty {
                    Text(tabs.prefix(3).joined(separator: " · ") + (tabs.count > 3 ? " +\(tabs.count - 3)" : ""))
                        .font(.caption).foregroundStyle(.tint).lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer(minLength: 6)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08)).frame(width: 70, height: 6)
                Capsule().fill(BrowserHeat.tint(bytes: bytes).opacity(0.85)).frame(width: max(3, 70 * fraction), height: 6)
            }
            Text(ResourceFormat.bytes(Double(bytes))).font(.callout.weight(.medium)).monospacedDigit().frame(minWidth: 68, alignment: .trailing)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

private struct BrowserEmptyHint: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 12))
    }
}

private struct BrowserSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.caption).frame(maxWidth: 150)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).accessibilityLabel("Aramayı temizle")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: .capsule)
    }
}

/// Uzun açıklamalar kartı kalabalıklaştırmasın diye (i) düğmesinde açılan küçük bilgi kutusu.
private struct BrowserInfoButton: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: { Image(systemName: "info.circle").foregroundStyle(.secondary) }
            .buttonStyle(.plain)
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true).frame(width: 320).padding(14)
            }
            .accessibilityLabel("Açıklama")
            .help("Açıklama")
    }
}

/// "Sekme RAM'ini ölç" düğmesi ve durumu. Ölçüm kullanıcı isteğiyledir; sekmelerde kısa bir JS döngüsü çalıştırır.
private struct TabProbeBar: View {
    let state: TabProbeState
    let mappedAt: Date?
    let safari: Bool
    let hasTabs: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: action) {
                    Label(mappedAt == nil ? "Sekme RAM'ini ölç" : "Yeniden ölç", systemImage: "scope")
                }
                .disabled(!hasTabs || isRunning)
                statusView
                Spacer(minLength: 0)
                BrowserInfoButton(text: "\(safari ? "Safari" : "Chrome") hangi sürecin hangi sekmeye ait olduğunu söylemez. Adalmon her sekmede yaklaşık 150 ms'lik boş bir JavaScript döngüsü çalıştırır ve hangi sürecin CPU süresinin arttığına bakar; böylece sekme başlığı ile süreç RAM'i eşleşir. Sayfanın içeriğine dokunulmaz. Aynı süreci paylaşan sekmelerde RAM “ortak” yazılır. Sekmeler değişince yeniden ölçmek gerekir.")
            }
            if state == .javascriptDisabled {
                Label("Safari › Ayarlar › Gelişmiş › “Web geliştiricileri için özellikleri göster”i açın, sonra menü çubuğunda Geliştir › Geliştirici Ayarları › “Apple Events’ten JavaScript’e izin ver”i işaretleyin. İşiniz bitince kapatabilirsiniz.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var isRunning: Bool { if case .running = state { true } else { false } }

    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .idle:
            Text("Her sekmenin RAM'ini başlığıyla görmek için ölçün.").font(.caption).foregroundStyle(.secondary)
        case .running(let done, let total):
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("\(done)/\(total) sekme").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
        case .finished(let mapped, let total):
            Text("\(mapped)/\(total) sekme eşlendi" + (mapped < total ? " · kalanlar belirsiz" : "")).font(.caption).foregroundStyle(.secondary)
        case .javascriptDisabled:
            EmptyView()
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.orange)
        }
    }
}
