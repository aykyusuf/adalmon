import SwiftUI

/// Pil paneli: Juicy düzeyinde ayrıntı. Üstte büyük yüzde + dilimli çubuk; altında daraltılabilir bölümler.
struct BatteryPanelView: View {
    /// Düşük güç modu: yardımcı kuruluysa değiştirilebilir, değilse yalnızca durum gösterilir.
    enum LowPowerControl: Equatable { case readOnly, toggle }

    let model: BatteryPanelModel
    let apps: [BatteryEnergyApp]
    let devices: [DeviceBattery]
    let lowPowerControl: LowPowerControl
    @Binding var config: PanelConfig
    let actions: PanelActions
    let opensMainWindow: Bool
    var maxHeight: CGFloat?

    @State private var lowPowerDraft = false

    var body: some View {
        PanelScaffold(kind: .battery, actions: actions, opensMainWindow: opensMainWindow, subtitle: model.statusTitle, maxHeight: maxHeight) {
            topCard
            PanelDetailSection(id: "battery.info", title: "Pil bilgisi", symbol: "info", tint: .cyan, config: $config) { EmptyView() } content: {
                health
                Divider().opacity(0.5)
                temperature
                Divider().opacity(0.5)
                power
                Divider().opacity(0.5)
                flow
                Divider().opacity(0.5)
                capacity
            }
            Button(action: { actions.openRoute(.battery) }) {
                HStack {
                    Label("Pil içgörülerini aç", systemImage: "chart.line.uptrend.xyaxis").font(.callout)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.quaternary, in: .rect(cornerRadius: 14, style: .continuous))
                .contentShape(.rect(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            if !apps.isEmpty {
                PanelDetailSection(id: "battery.apps", title: "Önemli enerji kullanan uygulamalar", symbol: "bolt.circle", tint: .orange, config: $config) {
                    Text("24 sa")
                } content: {
                    ForEach(apps.prefix(5)) { app in appRow(app) }
                }
            }
            if !devices.isEmpty {
                PanelDetailSection(id: "battery.devices", title: "Cihazlar", symbol: "airpodspro", tint: .blue, config: $config) {
                    Text("\(devices.count)")
                } content: {
                    ForEach(devices.prefix(8)) { DevicePanelRow(device: $0) }
                    if devices.count > 8 { Text("+\(devices.count - 8) cihaz daha").font(.caption2).foregroundStyle(.tertiary) }
                }
            }
        } footer: { EmptyView() }
        .onAppear { lowPowerDraft = model.lowPowerMode }
    }

    // MARK: Üst kart

    private var topCard: some View {
        PanelCard(tint: model.tint, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(model.level)")
                                .font(.system(size: 46, weight: .bold, design: .rounded))
                                .foregroundStyle(model.tint)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("%").font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(model.tint.opacity(0.8))
                        }
                        HStack(spacing: 5) {
                            if model.charging { Image(systemName: "bolt.fill").foregroundStyle(model.tint) }
                            else if model.isPluggedIn { Image(systemName: "powerplug.fill").foregroundStyle(model.tint) }
                            Text(model.statusTitle).font(.callout.weight(.semibold))
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(model.untilLabel).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                        Text(model.untilValue).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    .padding(.top, 6)
                    .accessibilityElement(children: .combine)
                }
                SegmentedCapacityBar(level: model.level, tint: model.tint, charging: model.charging, segments: 20, height: 9)
            }
        }
    }

    // MARK: Pil bilgisi alt blokları

    private func blockTitle(_ title: String, _ symbol: String, _ tint: Color) -> some View {
        Label(title, systemImage: symbol).labelStyle(PanelTitleLabelStyle(tint: tint)).font(.callout.weight(.semibold))
    }

    private var health: some View {
        VStack(alignment: .leading, spacing: 6) {
            blockTitle("Pil sağlığı", "heart.fill", model.healthTint)
            HStack(alignment: .firstTextBaseline) {
                Text(model.healthText).font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(model.healthTint).monospacedDigit()
                Text(model.healthWord).font(.callout.weight(.medium)).foregroundStyle(model.healthTint)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(model.cyclesText).font(.callout.weight(.semibold)).monospacedDigit()
                    Text("Döngü sayısı").font(.caption2).foregroundStyle(.secondary)
                }
            }
            UsageBar(fraction: model.healthFraction, tint: model.healthTint, height: 6)
            if let note = model.healthNote {
                Text("Apple \(model.healthText) · \(note)").font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Text("Döngü").font(.caption2).foregroundStyle(.secondary)
                UsageBar(fraction: model.cycleFraction, tint: .blue, height: 3)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var temperature: some View {
        VStack(alignment: .leading, spacing: 6) {
            blockTitle("Sıcaklık", "thermometer.medium", model.temperatureTint)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.celsiusText).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(model.temperatureTint).monospacedDigit()
                    Text(model.fahrenheitText).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Label(model.temperatureStatus, systemImage: "checkmark.circle.fill")
                        .labelStyle(PanelTitleLabelStyle(tint: model.temperatureTint)).font(.callout.weight(.semibold))
                    Text(model.temperatureNote).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var power: some View {
        VStack(alignment: .leading, spacing: 8) {
            blockTitle("Güç ve elektrik", "bolt.fill", .green)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    PanelStatTile(title: "Güç kullanımı", value: model.powerText)
                    PanelStatTile(title: "Voltaj", value: model.voltageText, caption: model.voltageNote)
                }
                GridRow {
                    PanelStatTile(title: "Akım", value: currentValue)
                    PanelStatTile(title: "Durum", value: model.chargingStateText, tint: model.currentDirection == .charging ? .green : .secondary)
                }
            }
            lowPowerRow
        }
    }

    private var currentValue: String {
        switch model.currentDirection {
        case .charging: "↑ " + model.currentText
        case .discharging: "↓ " + model.currentText
        case .idle: model.currentText
        }
    }

    @ViewBuilder
    private var lowPowerRow: some View {
        switch lowPowerControl {
        case .toggle:
            Toggle(isOn: $lowPowerDraft) { Label("Düşük güç modu", systemImage: "leaf.fill").font(.callout) }
                .toggleStyle(.switch).controlSize(.small)
                .onChange(of: lowPowerDraft) { _, new in if new != model.lowPowerMode { actions.setLowPowerMode(new) } }
        case .readOnly:
            PanelValueRow(title: "Düşük güç modu", value: model.lowPowerMode ? "Açık" : "Kapalı", tint: model.lowPowerMode ? .yellow : nil)
        }
    }

    private var flow: some View {
        VStack(alignment: .leading, spacing: 8) {
            blockTitle("Güç akışı", "bolt.horizontal.circle", .green)
            HStack(spacing: 8) {
                flowBox(symbol: model.isPluggedIn ? "powerplug.fill" : "battery.50percent", text: model.flowSourceText, width: 62)
                flowBox(symbol: nil, text: model.flowCenterText, width: nil, emphasized: true)
                flowBox(symbol: "laptopcomputer", text: nil, width: 46)
            }
            VStack(spacing: 2) {
                Label(model.flowNote, systemImage: "checkmark.circle.fill").labelStyle(PanelTitleLabelStyle(tint: .green)).font(.caption.weight(.semibold))
                Text(model.flowUsage).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                chip("ŞARJ ALETİ", model.chargerText)
                chip("KABLO", model.cableText)
                chip("MAC ÇEKİYOR", model.macTakesText)
            }
        }
    }

    private func flowBox(symbol: String?, text: String?, width: CGFloat?, emphasized: Bool = false) -> some View {
        VStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.secondary) }
            if let text {
                Text(text).font(emphasized ? .system(.title3, design: .rounded, weight: .semibold) : .caption.weight(.semibold)).monospacedDigit()
            }
        }
        .frame(maxWidth: width ?? .infinity, minHeight: 58)
        .background(.primary.opacity(emphasized ? 0.09 : 0.05), in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func chip(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 8.5, weight: .semibold)).tracking(0.4).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var capacity: some View {
        VStack(alignment: .leading, spacing: 6) {
            blockTitle("Kapasite ayrıntıları", "battery.100percent", .blue)
            PanelValueRow(title: "Kalan", value: model.remainingText, tint: .green)
            PanelValueRow(title: "Şu anki tam dolu", value: model.currentFullText, tint: .blue)
            PanelValueRow(title: "Tasarım kapasitesi", value: model.designText)
            HStack {
                Text("Güncellendi: \(model.updatedText)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Şimdi yenile", systemImage: "arrow.clockwise", action: actions.refreshBattery)
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.tint)
            }
            .padding(.top, 2)
        }
    }

    private func appRow(_ app: BatteryEnergyApp) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: AppCatalog.shared.icon(for: app.app)).resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.callout).lineLimit(1)
                UsageBar(fraction: app.share, tint: app.share > 0.5 ? .red : (app.share > 0.25 ? .orange : .yellow), height: 4)
            }
            Text(Format.percent(app.share)).font(.callout.weight(.medium)).monospacedDigit().frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
