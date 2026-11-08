import SwiftUI

/// Editor rows for the selected component (meant to sit inside a grouped `Form` section).
struct ComponentInspector: View {
    @Binding var component: MenuBarComponent
    let config: MenuBarConfig
    let values: WidgetValues
    let canMoveLeft: Bool
    let canMoveRight: Bool
    let onMove: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        header
            .onChange(of: component.primary) { _, newValue in
                component.thresholds = newValue.defaultThresholds
                component = component.normalized()
            }
            .onChange(of: component.secondary) {
                component = component.normalized()
            }

        LabeledContent("1. satır") {
            primaryPicker
        }
        LabeledContent("2. satır") {
            secondaryPicker
                .disabled(!component.visual.allowsSecondLine)
        }
        .help(component.visual.allowsSecondLine ? "İsteğe bağlı ikinci değer" : "\(component.visual.displayName) tek değer gösterir")

        LabeledContent("Tıklayınca açılacak panel") {
            Picker("Tıklayınca açılacak panel", selection: $component.panelKind) {
                Text("Otomatik (\(PanelRouter.automaticKind(for: component).displayName))").tag(PanelKind?.none)
                Divider()
                ForEach(PanelKind.allCases) { Text($0.displayName).tag(PanelKind?.some($0)) }
            }
            .labelsHidden()
            .fixedSize()
        }
        .help("Bu bileşene tıklayınca hangi panelin açılacağı. Otomatik: birinci satırdaki metriğin paneli.")

        VStack(alignment: .leading, spacing: 6) {
            Text("Görünüm")
            VisualChips(component: $component, config: config, values: values)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("Renk")
            ColorModePicker(component: $component)
        }
        colorControls

        if component.visual == .batteryCapsule {
            Toggle("Kalan / dolma süresini göster", isOn: $component.battery.showTime)
            Toggle("Durum renkleri (şarjda yeşil, azalınca turuncu, kritikte kırmızı)", isOn: $component.battery.statusColors)
            Picker("Boyut", selection: $component.battery.size) {
                ForEach(BatteryGlyphOptions.Size.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Animasyon", selection: $component.battery.motion) {
                ForEach(BatteryGlyphOptions.Animation.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Pildeki sıvının hareketi (yalnızca Mac pili). Canlı: sürekli dalga; Hafif: daha sakin. Hareketi Azalt açıkken durur, Düşük Güç Modunda yavaşlar.")
        }
        Toggle("Etiket göster", isOn: $component.showLabel)
        if component.visual.hasGraphic {
            Toggle("Değeri göster", isOn: $component.showValue)
        }
        if component.fields.contains(where: \.usesByteUnit) {
            Picker("Birim", selection: $component.unit) {
                ForEach(ByteUnit.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        if component.fields.contains(where: \.isTemperature) && values.temperature == nil {
            Text("Sıcaklık şu an okunamıyor; menü çubuğunda “—” görünür.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ComponentPreview(components: [component], config: config, values: values, zoom: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(component.title)
                    .font(.headline)
                    .lineLimit(2)
                Toggle("Menü çubuğunda göster", isOn: $component.enabled)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
            }
            Spacer(minLength: 8)
            ControlGroup {
                Button("Sola taşı", systemImage: "chevron.left") { onMove(-1) }
                    .disabled(!canMoveLeft)
                Button("Sağa taşı", systemImage: "chevron.right") { onMove(1) }
                    .disabled(!canMoveRight)
            }
            .labelStyle(.iconOnly)
            .fixedSize()
            Button("Sil", systemImage: "trash", role: .destructive, action: onDelete)
                .labelStyle(.iconOnly)
                .help("Bileşeni sil (⌫, menü çubuğu önizlemesi seçiliyken)")
        }
    }

    private var primaryPicker: some View {
        Picker("1. satır", selection: $component.primary) {
            ForEach(FieldCategory.allCases) { category in
                Section(category.displayName) {
                    ForEach(fields(in: category, includeConnection: true)) { field in
                        Text(field.displayName).tag(field)
                    }
                }
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var secondaryPicker: some View {
        Picker("2. satır", selection: $component.secondary) {
            Text("Yok").tag(DataField?.none)
            Divider()
            ForEach(FieldCategory.allCases.filter { $0 != .connection }) { category in
                Section(category.displayName) {
                    ForEach(fields(in: category, includeConnection: false)) { field in
                        Text(field.displayName).tag(DataField?.some(field))
                    }
                }
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func fields(in category: FieldCategory, includeConnection: Bool) -> [DataField] {
        DataField.allCases.filter { $0.category == category && (includeConnection || $0 != .connection) }
    }

    @ViewBuilder
    private var colorControls: some View {
        switch component.colorMode {
        case .custom:
            ColorPicker("Renk", selection: $component.customSwiftUIColor, supportsOpacity: false)
        case .gradient:
            ColorPicker("Düşük değer rengi", selection: $component.gradientStartSwiftUIColor, supportsOpacity: false)
            ColorPicker("Yüksek değer rengi", selection: $component.gradientEndSwiftUIColor, supportsOpacity: false)
        case .threshold:
            thresholdSlider("Turuncu eşiği", value: $component.thresholds.warning, range: 0.1...0.9)
            thresholdSlider("Kırmızı eşiği", value: $component.thresholds.critical, range: 0.15...1)
            if component.primary.isInverted {
                Text("Boş/kalan değerlerde renk ters işler: az boş alan kırmızı olur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .monochrome, .accent:
            EmptyView()
        }
        if component.colorMode != .monochrome && component.visual.hasGraphic {
            Picker("Renklendir", selection: $component.colorTarget) {
                ForEach(ColorTarget.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func thresholdSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: 0.05)
                    .onChange(of: value.wrappedValue) { normalizeThresholds() }
                Text(component.primary.isTemperature ? "\(Int((value.wrappedValue * 100).rounded())) °C" : Format.percent(value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    private func normalizeThresholds() {
        if component.thresholds.critical < component.thresholds.warning + 0.05 {
            component.thresholds.critical = min(1, component.thresholds.warning + 0.05)
        }
    }
}
