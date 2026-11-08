import SwiftUI

/// Dock penceresi › Pil sayfası: özet, sağlık/sıcaklık/döngü/güç kartları, grafikler, güç akışı, kapasite ve enerji yiyenler.
struct BatteryPage: View {
    let monitor: BatteryMonitor
    let store: UsageStore
    let router: SettingsRouter
    /// Cihazlar ve iPhone & iPad sekmeleri için (önizleme/testlerde verilmeyebilir).
    var devices: DeviceBatteryService?
    var prefs: Preferences?

    @State private var tab: BatteryTab
    @State private var levelRange: BatteryLevelRange = .h24
    @State private var energyRange: BatteryDayRange = .d7
    @State private var screenRange: BatteryDayRange = .d7
    @State private var tempMode: TempMode = .day
    @State private var data = PageData()

    init(monitor: BatteryMonitor, store: UsageStore, router: SettingsRouter, devices: DeviceBatteryService? = nil,
         prefs: Preferences? = nil, initialTab: BatteryTab = .mac) {
        self.monitor = monitor
        self.store = store
        self.router = router
        self.devices = devices
        self.prefs = prefs
        _tab = State(initialValue: initialTab)
    }

    enum TempMode: String, CaseIterable, Identifiable {
        case day = "24 sa", trend = "Trend"
        var id: String { rawValue }
    }

    struct PageData: Equatable {
        var levelSamples: [BatterySample] = []
        var tempSamples: [BatterySample] = []
        var daily: [BatteryDayRow] = []
        var loaded = false
    }

    private struct LoadKey: Hashable { var level: BatteryLevelRange; var mac: Bool }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: MainSection.battery.title) {
                    Button { router.open(.batteryAlerts) } label: {
                        Label("Pil uyarıları", systemImage: "bell.badge")
                    }
                    .buttonStyle(.link)
                    .help("Düşük pil, şarj seviyesi ve takıldı/çıkarıldı uyarılarını ayarla")
                }
                tabPicker
                switch tab {
                case .devices:
                    if let devices, let prefs { DevicesTab(service: devices, prefs: prefs, battery: monitor) }
                case .ios:
                    if let devices, let prefs { IOSDevicesTab(service: devices, prefs: prefs) }
                case .mac:
                    macContent
                }
            }
            .padding(24)
        }
        .task(id: LoadKey(level: levelRange, mac: tab == .mac)) {
            while !Task.isCancelled, tab == .mac {
                await load()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: tab) {
            devices?.setPageVisible(tab == .devices || tab == .ios)
            if tab == .ios { devices?.refreshIOS() }
        }
        .onDisappear { devices?.setPageVisible(false) }
    }

    private var tabPicker: some View {
        CapsuleTabBar(selection: $tab, accessibilityLabel: "Bölüm")
    }

    @ViewBuilder
    private var macContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if let r = monitor.reading {
                    hero(r)
                    statCards(r)
                    levelCard
                    ViewThatFits(in: .horizontal) {
                        VStack(spacing: 16) {
                            HStack(alignment: .top, spacing: 16) { energyCard.frame(minWidth: 380); screenCard.frame(minWidth: 380) }
                            HStack(alignment: .top, spacing: 16) { capacityCard(r).frame(minWidth: 380); cyclesCard(r).frame(minWidth: 380) }
                        }
                        VStack(spacing: 16) { energyCard; screenCard; capacityCard(r); cyclesCard(r) }
                    }
                    temperatureCard(r)
                    powerFlowCard(r)
                    capacityDetails(r)
                    if !monitor.energyApps.isEmpty { appsCard }
                } else {
                    ContentUnavailableView("Bu Mac'te pil yok", systemImage: "battery.0percent",
                                           description: Text("Pil verisi yalnızca dahili pili olan Mac'lerde gösterilir."))
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
        }
    }

    // MARK: Veri

    private func load() async {
        let now = Date.now
        let cal = UsageStore.keyCalendar
        let from = now.addingTimeInterval(-Double(levelRange.seconds))
        let level = await store.batterySamples(from: from, to: now, bucketSeconds: levelRange.bucketSeconds)
        let temp = await store.batterySamples(from: now.addingTimeInterval(-86_400), to: now, bucketSeconds: 300)
        let startDay = cal.date(byAdding: .day, value: -399, to: now) ?? now
        let daily = await store.batteryDaily(fromDay: UsageStore.dayKey(startDay, calendar: cal), toDay: UsageStore.dayKey(now, calendar: cal))
        let new = PageData(levelSamples: level, tempSamples: temp, daily: daily, loaded: true)
        if new != data { data = new }
        await monitor.refreshHistoryExtras()
    }

    private func dailyItems(_ range: BatteryDayRange, _ value: (BatteryDayRow) -> Double) -> [BatteryBarItem] {
        let cal = UsageStore.keyCalendar
        let byDay = Dictionary(uniqueKeysWithValues: data.daily.map { ($0.day, $0) })
        let today = cal.startOfDay(for: .now)
        return (0..<range.rawValue).reversed().compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            return BatteryBarItem(date: d, value: byDay[UsageStore.dayKey(d, calendar: cal)].map(value) ?? 0)
        }
    }

    private func dailyLine(_ value: (BatteryDayRow) -> Double?) -> [ChartPoint] {
        let cal = UsageStore.keyCalendar
        return data.daily.compactMap { row in
            guard let v = value(row), let date = Self.parse(row.day, cal) else { return nil }
            return ChartPoint(date: date.addingTimeInterval(43_200), value: v)
        }
    }

    private static func parse(_ day: String, _ cal: Calendar) -> Date? {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    // MARK: Kartlar

    private func hero(_ r: BatteryReading) -> some View {
        let tint = BatteryPalette.tint(r)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("%\(r.level)")
                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if r.isCharging { Image(systemName: "bolt.fill").font(.title).foregroundStyle(tint) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(BatteryFormat.statusLine(r)).font(.title3.weight(.medium))
                    Text(lastFullText).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if r.lowPowerMode {
                    Label("Düşük güç modu", systemImage: "leaf.fill").font(.caption.weight(.medium)).foregroundStyle(.yellow)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(.yellow.opacity(0.15), in: .capsule)
                }
            }
            SegmentedCapacityBar(level: r.level, tint: tint, charging: r.isCharging, segments: 40, height: 14)
        }
        .batteryCard(padding: 20)
        .accessibilityElement(children: .contain)
    }

    private var lastFullText: String {
        if let d = monitor.lastFullCharge { return "Son %100'e şarj: " + BatteryFormat.relativeDay(d) }
        return "Son %100'e şarj: henüz kayıt yok"
    }

    private func statCards(_ r: BatteryReading) -> some View {
        let cards = Group {
            StatCard(symbol: "heart.fill", title: "Sağlık", value: BatteryFormat.percent(r.primaryHealthPercent),
                     subtitle: r.appleMaxCapacityPercent != nil ? "Apple · ham %\(r.rawHealthPercent ?? 0)" : "ham oran (tam dolu ÷ tasarım)",
                     tint: BatteryPalette.healthTint(r.primaryHealthPercent), info: Self.healthInfo(r))
            StatCard(symbol: "thermometer.medium", title: "Sıcaklık", value: BatteryFormat.temp(r.temperatureC),
                     subtitle: BatteryFormat.temperatureStatus(r.temperatureC)?.title ?? "okunamadı", tint: BatteryPalette.tempTint(r.temperatureC),
                     info: "Pil sıcaklığı, sistemin gas gauge algılayıcısından okunur. 35 °C altı normaldir; 40 °C üstü sıcak sayılır.")
            StatCard(symbol: "arrow.triangle.2.circlepath", title: "Döngü", value: BatteryFormat.int(r.cycles),
                     subtitle: "/ \(BatteryFormat.int(r.cycleLimit)) · %\(Int((Double(r.cycles ?? 0) / Double(max(1, r.cycleLimit)) * 100).rounded())) kullanıldı",
                     tint: .blue, info: "Bir döngü, pilin toplamda bir tam şarj kadar kullanılmasıdır. Apple bu pil için \(r.cycleLimit) döngüde %80 kapasiteyi hedefler.")
            StatCard(symbol: "bolt.fill", title: "Güç", value: BatteryFormat.watts(r.macLoadW),
                     subtitle: r.isPluggedIn ? "Mac'in çektiği (adaptörden)" : "Mac'in çektiği (pilden)", tint: .orange,
                     info: "Sistemin o an harcadığı güç (PowerTelemetry SystemPowerIn). Pilde iken bataryadan, fişte iken adaptörden gelir.")
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { cards }.frame(minWidth: 760)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) { cards }
        }
    }

    static func healthInfo(_ r: BatteryReading) -> String {
        var s = "Maksimum kapasite (Apple): Ayarlar › Pil'de gösterilen değer, \(BatteryFormat.percent(r.appleMaxCapacityPercent))."
        s += "\nHam oran: tam dolu kapasite ÷ tasarım kapasitesi = \(BatteryFormat.int(r.rawMaxMAh)) / \(BatteryFormat.int(r.designMAh)) mAh = \(BatteryFormat.percent(r.rawHealthPercent)) (Juicy bu oranı gösterir)."
        s += "\nNominal: \(BatteryFormat.int(r.nominalMAh)) mAh = \(BatteryFormat.percent(r.nominalHealthPercent)). Üç sayı farklı ölçümlerdir; Apple'ınki kalibre edilmiş olandır."
        return s
    }

    private var levelCard: some View {
        ChartCard(title: "Pil seviyesi", symbol: "battery.75percent", trailing: {
            Picker("Aralık", selection: $levelRange) {
                ForEach(BatteryLevelRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }, footer: lastFullText + " · yeşil: şarj, mavi: pil") {
            if data.levelSamples.count < 2 {
                BatteryEmptyChart()
            } else {
                BatteryLevelChart(samples: data.levelSamples, range: levelRange).frame(height: 220)
            }
        }
    }

    private var energyCard: some View {
        let items = dailyItems(energyRange) { $0.consumedPercent }
        let used = items.filter { $0.value > 0 }
        let avg = used.isEmpty ? 0 : used.map(\.value).reduce(0, +) / Double(used.count)
        return ChartCard(title: "Günlük enerji kullanımı", symbol: "bolt.batteryblock", trailing: {
            RangePicker(selection: $energyRange)
        }, footer: "Gün boyu pilden düşen yüzdelerin toplamı · ortalama %\(Int(avg.rounded())) / gün") {
            if used.isEmpty { BatteryEmptyChart() } else {
                BatteryBarChart(items: items, tint: .orange, format: { "%\(Int($0.rounded())) pil" }, axisFormat: { "%\(Int($0))" }, title: "Enerji").frame(height: 180)
            }
        }
    }

    private var screenCard: some View {
        let items = dailyItems(screenRange) { Double($0.screenSeconds) / 3_600 }
        let used = items.filter { $0.value > 0 }
        let avg = used.isEmpty ? 0 : used.map(\.value).reduce(0, +) / Double(used.count)
        return ChartCard(title: "Ekran açık süresi", symbol: "display", trailing: {
            RangePicker(selection: $screenRange)
        }, footer: "Ekran açık ve oturum etkin olan süre · ortalama \(Self.hours(avg)) / gün") {
            if used.isEmpty { BatteryEmptyChart() } else {
                BatteryBarChart(items: items, tint: .purple, format: Self.hours, axisFormat: { "\(Int($0)) sa" }, title: "Ekran").frame(height: 180)
            }
        }
    }

    static func hours(_ h: Double) -> String { BatteryFormat.long(Int((h * 60).rounded())) }

    private func capacityCard(_ r: BatteryReading) -> some View {
        ChartCard(title: "Maksimum kapasite", symbol: "battery.100percent", trailing: {
            Text(BatteryFormat.mAh(r.rawMaxMAh)).font(.callout.weight(.semibold)).foregroundStyle(.green).monospacedDigit()
        }, footer: "Tam dolu kapasite (mAh) zamanla · düşüş eğrisi") {
            BatteryTrendLine(points: dailyLine { $0.maxCapacityMAh.map(Double.init) }, color: .green, name: "Kapasite",
                             format: { BatteryFormat.mAh(Int($0.rounded())) }, axisFormat: { BatteryFormat.int(Int($0.rounded())) }, minSpan: 60)
                .frame(height: 180)
        }
    }

    private func cyclesCard(_ r: BatteryReading) -> some View {
        ChartCard(title: "Döngü sayısı", symbol: "arrow.triangle.2.circlepath", trailing: {
            Text("\(BatteryFormat.int(r.cycles)) döngü").font(.callout.weight(.semibold)).foregroundStyle(.blue).monospacedDigit()
        }, footer: "Döngü sayısı her tam şarj kadar kullanımda bir artar") {
            BatteryTrendLine(points: dailyLine { $0.cycles.map(Double.init) }, color: .blue, name: "Döngü",
                             format: { "\(Int($0.rounded())) döngü" }, axisFormat: { "\(Int($0.rounded()))" }, minSpan: 4)
                .frame(height: 180)
        }
    }

    private func temperatureCard(_ r: BatteryReading) -> some View {
        let trend = dailyLine { $0.avgTemp }
        let day = data.tempSamples.compactMap { s in s.tempC.map { ChartPoint(date: Date(timeIntervalSince1970: TimeInterval(s.ts)), value: $0) } }
        let source = tempMode == .day ? day : trend
        let stats = ChartStats(values: source.map(\.value))
        return ChartCard(title: "Sıcaklık", symbol: "flame.fill", trailing: {
            HStack(spacing: 10) {
                Picker("Görünüm", selection: $tempMode) { ForEach(TempMode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                Text(BatteryFormat.temp(r.temperatureC)).font(.callout.weight(.semibold)).foregroundStyle(BatteryPalette.tempTint(r.temperatureC)).monospacedDigit()
            }
        }, footer: tempMode == .day ? "Son 24 saat" : "Günlük ortalama sıcaklık") {
            VStack(spacing: 10) {
                BatteryTrendLine(points: source, color: .orange, name: "Sıcaklık", format: { BatteryFormat.temp($0) },
                                 axisFormat: { "\(Int($0.rounded()))°" },
                                 timeLabel: { tempMode == .day ? $0.formatted(.dateTime.hour().minute()) : $0.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "tr_TR"))) },
                                 xLabel: { tempMode == .day ? $0.formatted(.dateTime.hour()) : $0.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "tr_TR"))) },
                                 minSpan: 6)
                    .frame(height: 180)
                if let stats {
                    HStack {
                        tempStat("Ort", stats.average); Spacer(); tempStat("Min", stats.minimum); Spacer(); tempStat("Maks", stats.maximum)
                    }
                    .padding(.horizontal, 40)
                }
            }
        }
    }

    private func tempStat(_ label: String, _ v: Double) -> some View {
        VStack(spacing: 1) {
            Text(v.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "tr_TR"))) + "°").font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func powerFlowCard(_ r: BatteryReading) -> some View {
        ChartCard(title: "Güç akışı", symbol: "bolt.circle", trailing: {
            Text(r.isPluggedIn ? "Adaptör bağlı" : "Pil kullanılıyor").font(.callout).foregroundStyle(.secondary)
        }, footer: r.isPluggedIn ? "Adaptör Mac'e ve (şarj oluyorsa) pile dağılır; kalınlık ve hız watt ile orantılı. Değerler PowerTelemetry'den." : "Pilde iken Mac'in çektiği güç doğrudan bataryadan gelir.") {
            PowerFlowView(model: PowerFlowModel.make(r, deviceLevels: (devices?.devices ?? [])))
        }
    }

    private func capacityDetails(_ r: BatteryReading) -> some View {
        ChartCard(title: "Kapasite ve elektrik ayrıntıları", symbol: "list.bullet.rectangle", trailing: { EmptyView() }, footer: nil) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                detailRow("Kalan", BatteryFormat.mAh(r.rawCurrentMAh), "Tam dolu (ham)", BatteryFormat.mAh(r.rawMaxMAh))
                detailRow("Tasarım", BatteryFormat.mAh(r.designMAh), "Nominal", BatteryFormat.mAh(r.nominalMAh))
                detailRow("Sağlık (Apple)", BatteryFormat.percent(r.appleMaxCapacityPercent), "Sağlık (ham)", BatteryFormat.percent(r.rawHealthPercent))
                detailRow("Gerilim", r.voltageMV.map { String(format: "%.2f V", Double($0) / 1000) } ?? "—", "Akım", r.amperageMA.map { "\(BatteryFormat.int($0)) mA" } ?? "—")
                detailRow("Adaptör", r.isPluggedIn ? (r.adapterDisplayName ?? "—") : "Yok", "Adaptör gücü", r.isPluggedIn ? (r.adapterLabelWatts.map { "\($0) W" } ?? "—") : "—")
                detailRow("Düşük güç modu", r.lowPowerMode ? "Açık" : "Kapalı", "Pil gücü", BatteryFormat.watts(r.batteryPowerW))
            }
        }
    }

    private func detailRow(_ a: String, _ av: String, _ b: String, _ bv: String) -> some View {
        GridRow {
            Text(a).foregroundStyle(.secondary)
            Text(av).fontWeight(.medium).monospacedDigit().lineLimit(1)
            Text(b).foregroundStyle(.secondary)
            Text(bv).fontWeight(.medium).monospacedDigit().lineLimit(1)
        }
        .font(.callout)
    }

    private var appsCard: some View {
        ChartCard(title: "Enerji yiyen uygulamalar", symbol: "flame", trailing: {
            Text("Son 24 saat").font(.callout).foregroundStyle(.secondary)
        }, footer: "Uygulamaların enerji etkisi (coalition ri_energy) payı") {
            VStack(spacing: 8) {
                ForEach(monitor.energyApps) { app in
                    HStack(spacing: 10) {
                        Text(app.name).lineLimit(1).frame(width: 190, alignment: .leading)
                        UsageBar(fraction: app.share, tint: .orange, height: 8)
                        Text(Format.percent(app.share)).monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
                    }
                    .font(.callout)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Bileşenler

private struct RangePicker: View {
    @Binding var selection: BatteryDayRange
    var body: some View {
        Picker("Aralık", selection: $selection) { ForEach(BatteryDayRange.allCases) { Text($0.title).tag($0) } }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
    }
}

struct ChartCard<Trailing: View, Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var trailing: Trailing
    var footer: String?
    @ViewBuilder var content: Content

    init(title: String, symbol: String, @ViewBuilder trailing: () -> Trailing, footer: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing()
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol).font(.headline)
                Spacer(minLength: 8)
                trailing
            }
            content
            if let footer {
                Label(footer, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            }
        }
        .batteryCard()
    }
}

struct StatCard: View {
    let symbol: String
    let title: String
    let value: String
    let subtitle: String
    let tint: Color
    var info: String?
    @State private var showInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: symbol).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if info != nil {
                    Button { showInfo.toggle() } label: { Image(systemName: "info.circle").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(title) hakkında bilgi")
                        .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                            Text(info ?? "").font(.callout).frame(width: 300, alignment: .leading).padding(14)
                        }
                }
            }
            Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
        }
        .batteryCard(padding: 14)
        .help(info ?? "")
        .accessibilityElement(children: .combine)
    }
}
