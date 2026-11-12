import AppKit
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
            // Seçim başka bileşene geçince de `primary` değişmiş görünür; yalnızca aynı bileşendeki düzenlemeye tepki ver
            // (aksi halde yeni seçilen bileşenin özel eşikleri varsayılana dönüyordu — SETTINGS-BUG-01).
            .onChange(of: ComponentFieldKey(id: component.id, field: component.primary)) { old, new in
                guard new.isEdit(from: old), let oldField = old.field else { return }
                component.applyPrimaryEdit(from: oldField)
            }
            .onChange(of: ComponentFieldKey(id: component.id, field: component.secondary)) { old, new in
                guard new.isEdit(from: old) else { return }
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
                ForEach(PanelKind.allCases.filter { $0 != .agents }) { Text($0.displayName).tag(PanelKind?.some($0)) }
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
            Toggle("Durum renkleri", isOn: $component.battery.statusColors)
            Text(BatteryGlyph.statusColorsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Boyut", selection: $component.battery.size) {
                ForEach(BatteryGlyphOptions.Size.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Animasyon", selection: $component.battery.motion) {
                ForEach(BatteryGlyphOptions.Animation.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Pildeki sıvının hareketi (yalnızca Mac pili). Canlı: sürekli dalga; Hafif: daha sakin. Hareketi Azalt açıkken durur, Düşük Güç Modunda yavaşlar.")
            BatteryStylePicker(style: $component.battery.style, fillColor: $component.battery.fillColor,
                               secondColor: $component.battery.secondColor, statusColors: component.battery.statusColors,
                               motion: component.battery.motion, values: values)
            BatteryBoltPicker(bolt: $component.battery.bolt)
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
            ThresholdColorsEditor(thresholds: $component.thresholds, colors: $component.levelColors, field: component.primary)
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
}

/// Şarj şimşeği: stil (Otomatik / Sabit / Nabız / Parıltı / Akış) ve renk (Otomatik / Sarı / Yeşil / Beyaz / Özel).
/// Hareket "Animasyon" ayarına tabidir (Kapalı, Hareketi Azalt ve Düşük Güç Modunda şimşek statik kalır).
struct BatteryBoltPicker: View {
    @Binding var bolt: BatteryBoltOptions

    private static let customDefault = RGBAColor(hex: "#FF4FA3") ?? BatteryGlyphOptions.Swatch.pink.color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Şimşek", selection: $bolt.style) {
                ForEach(BatteryBoltOptions.Style.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Şarj olurken pilin solundaki şimşek. " + bolt.style.help + ". Fişteyken ama şarj olmazken şimşek hareket etmez.")
            HStack(spacing: 6) {
                Text("Şimşek rengi")
                ForEach(BatteryBoltOptions.Tone.allCases.filter { $0 != .custom }) { tone in
                    chip(tone.displayName, selected: bolt.tone == tone) { bolt.tone = tone }
                }
                chip(BatteryBoltOptions.Tone.custom.displayName, selected: bolt.tone == .custom) {
                    bolt.tone = .custom
                    if bolt.custom == nil { bolt.custom = Self.customDefault }
                }
                ColorPicker("Özel şimşek rengi", selection: customBinding, supportsOpacity: false)
                    .labelsHidden()
                    .opacity(bolt.tone == .custom ? 1 : 0.4)
            }
            if bolt.tone != .auto {
                Text("Seçili renk, şarj gücüne göre değişen otomatik rengin yerine geçer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var customBinding: Binding<Color> {
        Binding {
            Color(nsColor: (bolt.custom ?? Self.customDefault).nsColor)
        } set: {
            bolt.custom = RGBAColor(NSColor($0))
            bolt.tone = .custom
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(selected ? Color.accentColor.opacity(0.2) : Color.clear, in: .capsule)
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 1.5 : 0.5))
    }
}

/// Pil animasyon stili ızgarası + dolgu rengi seçici. Izgara statik (stilin önizleme fazında tek kare); yalnızca seçili
/// hücre, görünürken tek hafif zaman çizelgesiyle (10 fps) canlı döner — Hareketi Azalt ya da Kapalı'da o da durur.
struct BatteryStylePicker: View {
    @Binding var style: BatteryGlyphOptions.Style
    @Binding var fillColor: RGBAColor?
    @Binding var secondColor: RGBAColor?
    let statusColors: Bool
    let motion: BatteryGlyphOptions.Animation
    let values: WidgetValues

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let zoom: CGFloat = 2
    private static let loop: TimeInterval = 2

    private var appearance: NSAppearance {
        NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
    }

    private var previewState: BatteryGlyphState {
        var s = values.battery ?? BatteryGlyphState(BatteryReading.sample)
        s.timeText = nil
        s.deviceSymbol = nil
        s.isApproximate = false
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Animasyon stili")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(BatteryGlyphOptions.Style.allCases) { item in
                    cell(item)
                }
            }
            colorRow
            if style.usesSecondColor {
                secondRow
            }
            if fillColor != nil {
                Text("Özel renkte de pil %10 ve altına inince kırmızı uyarı nabzı gösterilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func frame(_ item: BatteryGlyphOptions.Style, phase: Double) -> NSImage {
        let options = BatteryGlyphOptions(statusColors: statusColors, size: .medium, motion: .live, style: item,
                                          fillColor: fillColor, secondColor: secondColor)
        let key = BatteryFrameKey(state: previewState, options: options, appearance: appearance.name, scale: 2 * Self.zoom)
        return BatteryFrameRenderer.frame(key, appearance: appearance, phase: phase)
    }

    @ViewBuilder
    private func glyph(_ item: BatteryGlyphOptions.Style) -> some View {
        let size = BatteryGlyph.capsuleSize(BatteryGlyph.metrics(.medium), previewState)
        Group {
            // Canlı önizleme bilerek yok: 10 fps TimelineView tüm ayar penceresini yeniden değerlendirip %70 CPU yiyordu.
            // Menü çubuğundaki pil zaten canlı; ızgara her stili en güzel karesinde gösterir.
            Image(nsImage: frame(item, phase: item.previewPhase)).resizable().interpolation(.high)
        }
        .frame(width: size.width * Self.zoom, height: size.height * Self.zoom)
    }

    private func cell(_ item: BatteryGlyphOptions.Style) -> some View {
        let selected = item == style
        return Button { style = item } label: {
            VStack(spacing: 4) {
                glyph(item)
                Text(item.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(colorScheme == .dark ? Color(white: 0.11) : Color(white: 0.985), in: .rect(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 2 : 0.5))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(selected ? Color.accentColor.opacity(0.2) : Color.clear, in: .capsule)
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 1.5 : 0.5))
    }

    private var colorRow: some View {
        HStack(spacing: 6) {
            Text("Renk")
            chip("Otomatik", selected: fillColor == nil) { fillColor = nil }
                .help("Durum renkleri: " + BatteryGlyph.statusColorsCaption)
            ForEach(BatteryGlyphOptions.Swatch.allCases) { swatch in
                let selected = fillColor == swatch.color
                Button { fillColor = swatch.color } label: {
                    Circle()
                        .fill(Color(nsColor: swatch.color.nsColor))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
                        .padding(2)
                        .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .help(swatch.displayName)
                .accessibilityLabel(swatch.displayName)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            let isCustom = fillColor != nil && !BatteryGlyphOptions.Swatch.allCases.contains { $0.color == fillColor }
            chip("Özel", selected: isCustom) { if fillColor == nil || !isCustom { fillColor = Self.customDefault } }
                .help("Kendi rengini seç: sağdaki kutuya tıkla")
            ColorPicker("Özel renk", selection: colorBinding($fillColor, fallback: Self.customDefault),
                        supportsOpacity: false)
                .labelsHidden()
                .opacity(isCustom ? 1 : 0.4)
                .help("Özel renk")
        }
    }

    /// Hazır renklerden farklı bir başlangıç: "Özel"e basınca seçimin gerçekten değişmesi için.
    private static let customDefault = RGBAColor(hex: "#7B5CFF") ?? BatteryGlyphOptions.Swatch.purple.color
    private static let secondDefault = RGBAColor(hex: "#FF7A59") ?? BatteryGlyphOptions.Swatch.orange.color

    private var secondRow: some View {
        HStack(spacing: 6) {
            Text("İkinci renk")
            chip("Otomatik", selected: secondColor == nil) { secondColor = nil }
                .help(style == .stripes ? "Şeritler dolgunun açık tonuyla çizilir" : "Birinci renkten türetilir")
            chip("Özel", selected: secondColor != nil) { if secondColor == nil { secondColor = Self.secondDefault } }
                .help("Kendi rengini seç: sağdaki kutuya tıkla")
            ColorPicker("İkinci renk", selection: colorBinding($secondColor, fallback: Self.secondDefault),
                        supportsOpacity: false)
                .labelsHidden()
                .opacity(secondColor != nil ? 1 : 0.4)
        }
    }

    private func colorBinding(_ source: Binding<RGBAColor?>, fallback: RGBAColor) -> Binding<Color> {
        Binding {
            Color(nsColor: (source.wrappedValue ?? fallback).nsColor)
        } set: {
            source.wrappedValue = RGBAColor(NSColor($0))
        }
    }
}
