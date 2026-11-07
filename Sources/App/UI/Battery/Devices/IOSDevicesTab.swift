import SwiftUI
import UniformTypeIdentifiers

/// Pil › iPhone & iPad: libimobiledevice ile okunan sağlık, döngü, kapasite ve ömür boyu veriler.
struct IOSDevicesTab: View {
    let service: DeviceBatteryService
    let prefs: Preferences
    @State private var selectedUDID: String?
    @State private var includeSerials = true
    @State private var copied: String?

    private var selected: IOSDeviceDetails? {
        service.iosDevices.first { $0.udid == selectedUDID } ?? service.iosDevices.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let d = selected {
                if service.iosDevices.count > 1 { devicePicker }
                hero(d)
                cards(d)
                capacityCard(d)
                batteryCard(d)
                lifetimeCard(d)
                exportCard(d)
            } else {
                emptyState
            }
            settings
        }
    }

    // MARK: Üst

    private var devicePicker: some View {
        Picker("Cihaz", selection: Binding(get: { selected?.udid ?? "" }, set: { selectedUDID = $0 })) {
            ForEach(service.iosDevices) { Text($0.name).tag($0.udid) }
        }
        .pickerStyle(.segmented).labelsHidden()
    }

    private func hero(_ d: IOSDeviceDetails) -> some View {
        HStack(spacing: 14) {
            Image(systemName: d.productType.hasPrefix("iPad") ? "ipad" : "iphone").font(.system(size: 34)).foregroundStyle(.secondary).frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(d.name).font(.title3.weight(.semibold))
                Text([d.modelName, d.systemVersion.map { "iOS \($0)" }].compactMap(\.self).joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                Text("Son okuma \(d.fetchedAt.formatted(.dateTime.hour().minute())) · \(d.connection.title)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
            Button("Yenile", systemImage: "arrow.clockwise") { service.refreshIOS(force: true) }
        }
        .batteryCard(padding: 16)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch service.iosStatus {
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).lineLimit(2).frame(maxWidth: 260, alignment: .trailing)
        case .noDevice:
            Label("Cihaz şu an bağlı değil · son bilinen değerler", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    // MARK: Kartlar

    private func cards(_ d: IOSDeviceDetails) -> some View {
        let tiles = Group {
            StatCard(symbol: "heart.fill", title: "Sağlık", value: BatteryFormat.percent(d.healthPercent),
                     subtitle: d.rawHealthPercent.map { "ham %\($0)" } ?? "maksimum kapasite", tint: BatteryPalette.healthTint(d.healthPercent),
                     info: "Maksimum kapasite: pilin tam dolu kapasitesinin tasarım kapasitesine oranı (NominalChargeCapacity ÷ DesignCapacity). iOS Ayarlar › Pil › Pil Sağlığı ile aynı ölçüdür.")
            StatCard(symbol: d.isCharging ? "bolt.fill" : "battery.75percent", title: "Şarj", value: BatteryFormat.percent(d.level),
                     subtitle: d.isCharging ? "Şarj oluyor" : (d.fullyCharged ? "Tam şarjlı" : (d.externalConnected ? "Bağlı" : "Pilde")),
                     tint: DevicePalette.tint(level: d.level))
            StatCard(symbol: "arrow.triangle.2.circlepath", title: "Döngü", value: BatteryFormat.int(d.cycleCount), subtitle: "/ 1.000 döngüde ~%80 hedef", tint: .blue)
            StatCard(symbol: "thermometer.medium", title: "Sıcaklık", value: BatteryFormat.temp(d.temperatureC),
                     subtitle: BatteryFormat.temperatureStatus(d.temperatureC)?.title ?? "okunamadı", tint: BatteryPalette.tempTint(d.temperatureC))
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { tiles }.frame(minWidth: 700)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) { tiles }
        }
    }

    private func capacityCard(_ d: IOSDeviceDetails) -> some View {
        ChartCard(title: "Kapasite", symbol: "bolt.batteryblock", trailing: { EmptyView() }, footer: "Gerilim ve akım okuma anındaki değerlerdir; eksi akım = deşarj.") {
            detailGrid([
                ("Tam dolu (nominal)", BatteryFormat.mAh(d.nominalMAh)), ("Tasarım", BatteryFormat.mAh(d.designMAh)),
                ("Tam dolu (ham)", BatteryFormat.mAh(d.rawMaxMAh)), ("Kalan (ham)", BatteryFormat.mAh(d.rawCurrentMAh)),
                ("Gerilim", d.voltageMV.map { String(format: "%.2f V", Double($0) / 1000).replacingOccurrences(of: ".", with: ",") } ?? "—"),
                ("Akım", d.amperageMA.map { BatteryFormat.int($0) + " mA" } ?? "—"),
            ])
        }
    }

    private func batteryCard(_ d: IOSDeviceDetails) -> some View {
        ChartCard(title: "Pil", symbol: "battery.100percent", trailing: { EmptyView() }, footer: nil) {
            VStack(spacing: 8) {
                copyRow("Üretici", d.manufacturer)
                copyRow("Hücre gerilimleri", d.cellVoltagesMV.isEmpty ? nil : d.cellVoltagesMV.map { "\($0) mV" }.joined(separator: ", "))
                copyRow("Şarj aleti", d.adapterWatts.map { "\($0) W" + (d.adapterName.map { " · " + $0.trimmingCharacters(in: .whitespaces) } ?? "") }
                        ?? (d.externalConnected ? "Bağlı" : nil))
                copyRow("Pil seri no", d.batterySerial)
                copyRow("Cihaz seri no", d.deviceSerial)
            }
        }
    }

    private func lifetimeCard(_ d: IOSDeviceDetails) -> some View {
        let range = d.lifetimeMinTempC.flatMap { lo in d.lifetimeMaxTempC.map { BatteryFormat.temp(lo) + " … " + BatteryFormat.temp($0) } }
        let volts = d.lifetimeMinVoltageMV.flatMap { lo in d.lifetimeMaxVoltageMV.map { String(format: "%.2f … %.2f V", Double(lo) / 1000, Double($0) / 1000).replacingOccurrences(of: ".", with: ",") } }
        return ChartCard(title: "Ömür boyu", symbol: "clock.arrow.circlepath", trailing: { EmptyView() },
                         footer: "Pil denetleyicisinin ömür boyu kaydettiği değerler; her iPhone modeli hepsini vermeyebilir.") {
            detailGrid([
                ("Ortalama sıcaklık", BatteryFormat.temp(d.lifetimeAvgTempC)), ("Sıcaklık aralığı", range ?? "—"),
                ("En yüksek şarj akımı", d.lifetimeMaxChargeMA.map { BatteryFormat.int($0) + " mA" } ?? "—"),
                ("En yüksek deşarj akımı", d.lifetimeMaxDischargeMA.map { BatteryFormat.int($0) + " mA" } ?? "—"),
                ("Gerilim aralığı", volts ?? "—"),
                ("Çalışma süresi", d.lifetimeOperatingHours.map { "\(BatteryFormat.int($0)) sa (\($0 / 24) gün)" } ?? "—"),
            ])
        }
    }

    private func exportCard(_ d: IOSDeviceDetails) -> some View {
        ChartCard(title: "Dışa aktar", symbol: "square.and.arrow.up", trailing: { EmptyView() }, footer: nil) {
            HStack(spacing: 12) {
                Button("Raporu kopyala", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(IOSDeviceReport.text(d, includeSerials: includeSerials), forType: .string)
                    flash("report")
                }
                Button("Dosya olarak kaydet…", systemImage: "square.and.arrow.down") { save(d) }
                Toggle("Seri numaralarını ekle", isOn: $includeSerials).toggleStyle(.checkbox)
                if copied == "report" { Label("Kopyalandı", systemImage: "checkmark").foregroundStyle(.green).font(.callout) }
                Spacer()
            }
        }
    }

    // MARK: Parçalar

    private func detailGrid(_ rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
            ForEach(Array(stride(from: 0, to: rows.count, by: 2)), id: \.self) { i in
                GridRow {
                    Text(rows[i].0).foregroundStyle(.secondary)
                    Text(rows[i].1).fontWeight(.medium).monospacedDigit().lineLimit(1)
                    if i + 1 < rows.count {
                        Text(rows[i + 1].0).foregroundStyle(.secondary)
                        Text(rows[i + 1].1).fontWeight(.medium).monospacedDigit().lineLimit(1)
                    }
                }
                .font(.callout)
            }
        }
    }

    private func copyRow(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
            Text(value ?? "—").fontWeight(.medium).textSelection(.enabled).lineLimit(1)
            Spacer()
            if let value {
                Button(copied == title ? "Kopyalandı" : "Kopyala", systemImage: copied == title ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    flash(title)
                }
                .labelStyle(.iconOnly).buttonStyle(.borderless).help("Kopyala")
            }
        }
        .font(.callout)
    }

    private func flash(_ key: String) {
        copied = key
        Task { try? await Task.sleep(for: .seconds(1.6)); if copied == key { copied = nil } }
    }

    private func save(_ d: IOSDeviceDetails) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = IOSDeviceReport.fileName(d)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? IOSDeviceReport.text(d, includeSerials: includeSerials).write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Boş durum ve ayar

    @ViewBuilder
    private var emptyState: some View {
        switch service.iosStatus {
        case .libraryMissing:
            ContentUnavailableView("iPhone & iPad desteği yüklenemedi", systemImage: "externaldrive.badge.xmark",
                                   description: Text("libimobiledevice bu kurulumda bulunamadı ya da yüklenemedi. Uygulamayı yeniden kur; Bluetooth cihazları yine çalışır."))
                .frame(maxWidth: .infinity, minHeight: 280)
        case .failed(let message):
            ContentUnavailableView("Cihaza ulaşılamadı", systemImage: "exclamationmark.triangle", description: Text(message))
                .frame(maxWidth: .infinity, minHeight: 280)
        case .searching:
            ProgressView("Cihazlar aranıyor…").frame(maxWidth: .infinity, minHeight: 280)
        default:
            ContentUnavailableView {
                Label("iPhone veya iPad bağla", systemImage: "cable.connector")
            } description: {
                Text("1. iPhone'u USB ile bir kez bağla ve cihazda “Güven”e dokun.\n2. Wi‑Fi'de görünmesi için Finder'da cihazı seç › “Bu iPhone Wi‑Fi üzerinden eşitle”yi aç.\nSonra kablo olmadan da okunur: sağlık, döngü, sıcaklık ve ömür boyu veriler.")
            } actions: {
                Button("Şimdi ara", systemImage: "magnifyingglass") { service.refreshIOS(force: true) }
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Wi‑Fi'deyken bu iPhone'u göster", isOn: Bindable(prefs).deviceIncludeWifi)
                .onChange(of: prefs.deviceIncludeWifi) { service.refreshIOS(force: true) }
            Text("Wi‑Fi için cihazın bu Mac'e eşleşmiş (Güven) ve “Wi‑Fi üzerinden eşitle” açık olması gerekir. İlk Wi‑Fi okumasında macOS yerel ağ izni sorabilir.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
