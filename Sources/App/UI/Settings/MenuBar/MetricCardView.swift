import SwiftUI

/// One simple settings card: show switch, value checkboxes, layout and color options.
struct MetricCardView: View {
    @Binding var card: MetricCardConfig
    let config: MenuBarConfig
    let values: WidgetValues
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMove: (Int) -> Void
    @State private var showsColorDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if card.shown && card.kind != .connection {
                details
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Label(card.kind.displayName, systemImage: card.kind.settingsSymbol)
                .labelStyle(.titleAndIcon)
                .font(.headline)
                .lineLimit(1)
                .fixedSize()
            if card.shown {
                ComponentPreview(components: card.components(), config: config, values: values, zoom: 1)
            }
            Spacer(minLength: 8)
            Group {
                Button("Yukarı taşı", systemImage: "chevron.up") { onMove(-1) }
                    .disabled(!canMoveUp)
                Button("Aşağı taşı", systemImage: "chevron.down") { onMove(1) }
                    .disabled(!canMoveDown)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Menü çubuğundaki sırasını değiştir")
            // Narrow rows (CPU with a graph preview) keep the switch and drop its visible title.
            ViewThatFits(in: .horizontal) {
                showToggle
                showToggle
                    .labelsHidden()
                    .help("Menü çubuğunda göster")
            }
        }
    }

    private var showToggle: some View {
        Toggle("Menü çubuğunda göster", isOn: $card.shown)
            .toggleStyle(.switch)
            .controlSize(.small)
            .fixedSize()
    }

    @ViewBuilder
    private var details: some View {
        if card.kind == .battery {
            HStack(spacing: 14) {
                Toggle("Süreyi göster", isOn: $card.showTime)
                Toggle("Durum rengi (şarj / düşük)", isOn: $card.thresholdColor)
            }
            .toggleStyle(.checkbox)
            Text(BatteryGlyph.statusColorsCaption)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Animasyon", selection: $card.batteryAnimation) {
                ForEach(BatteryGlyphOptions.Animation.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Pildeki sıvının hareketi. Canlı: sürekli dalga; Hafif: daha sakin. Hareketi Azalt açıkken durur, Düşük Güç Modunda yavaşlar.")
            BatteryStylePicker(style: $card.batteryStyle, fillColor: $card.batteryFill, secondColor: $card.batterySecond,
                               statusColors: card.thresholdColor, motion: card.batteryAnimation, values: values)
            Text("Mac pilini kapsül içinde yüzde olarak gösterir. Cihaz pilleri (iPhone, AirPods…) ayrı menü çubuğu öğeleri olarak, pil panelinden eklenir.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            genericDetails
        }
    }

    @ViewBuilder
    private var genericDetails: some View {
        LabeledContent("Göster") {
            HStack(spacing: 14) {
                ForEach(card.kind.options) { field in
                    Toggle(card.kind.optionTitle(field), isOn: selection(field))
                        .disabled(card.isSelected(field) && !card.canDeselect(field))
                }
                if card.kind.graphField != nil {
                    Toggle("Grafik", isOn: graph)
                        .disabled(card.showGraph && !card.canDeselectGraph)
                }
            }
            .toggleStyle(.checkbox)
        }
        if card.kind == .network {
            Picker("Kaynak", selection: $card.networkSource) {
                ForEach(NetworkCardSource.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        if !card.fields.isEmpty {
            Picker("Düzen", selection: $card.layout) {
                ForEach(MetricLayout.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        HStack(spacing: 14) {
            Toggle("Renk: eşiğe göre", isOn: $card.thresholdColor)
            Toggle("Etiket", isOn: $card.showLabel)
        }
        .toggleStyle(.checkbox)
        if card.thresholdColor {
            DisclosureGroup("Renkler ve eşikler", isExpanded: $showsColorDetails) {
                ThresholdColorsEditor(thresholds: $card.effectiveThresholds, colors: $card.levelColors, field: card.thresholdField)
            }
        }
    }

    private func selection(_ field: DataField) -> Binding<Bool> {
        Binding { card.isSelected(field) } set: { card.set(field, selected: $0) }
    }

    private var graph: Binding<Bool> {
        Binding { card.showGraph } set: { card.setGraph($0) }
    }
}
