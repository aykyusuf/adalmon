import AppKit
import SwiftUI

/// Eşik renk modunun ayarları: iki eşik ve seviye başına renk (Varsayılan / Renksiz / Özel).
/// Basit kart ve Gelişmiş düzenleyici aynı görünümü kullanır. Alanlara doğrudan bağlanır (`.onChange` yok).
struct ThresholdColorsEditor: View {
    @Binding var thresholds: Thresholds
    @Binding var colors: ThresholdColors
    /// Eşik ölçeğini belirleyen alan (°C / %, boş/kalan notu).
    let field: DataField?

    var body: some View {
        slider("Uyarı eşiği", value: warning, range: 0.1...0.9)
        slider("Kritik eşiği", value: critical, range: 0.15...1)
        if field?.isInverted == true {
            Text("Boş/kalan değerlerde renk ters işler: az boş alan kritik seviyeye girer.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(ThresholdLevel.allLevels, id: \.self) { level in
            LevelColorRow(level: level, color: $colors[level])
        }
    }

    private var warning: Binding<Double> {
        Binding { thresholds.warning } set: {
            var t = thresholds
            t.warning = $0
            if t.critical < t.warning + 0.05 { t.critical = min(1, t.warning + 0.05) }
            thresholds = t
        }
    }

    private var critical: Binding<Double> {
        Binding { thresholds.critical } set: {
            var t = thresholds
            t.critical = $0
            if t.critical < t.warning + 0.05 { t.critical = min(1, t.warning + 0.05) }
            thresholds = t
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: 0.05)
                Text(field?.isTemperature == true ? "\(Int((value.wrappedValue * 100).rounded())) °C" : Format.percent(value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }
}

/// Tek seviyenin renk seçimi.
private struct LevelColorRow: View {
    let level: ThresholdLevel
    @Binding var color: LevelColor

    private enum Choice: Hashable { case automatic, none, custom }

    private var defaultName: String {
        switch level {
        case .normal: "yeşil"
        case .warning: "turuncu"
        case .critical: "kırmızı"
        }
    }

    private var choice: Binding<Choice> {
        Binding {
            switch color {
            case .automatic: .automatic
            case .none: .none
            case .custom: .custom
            }
        } set: { new in
            switch new {
            case .automatic: color = .automatic
            case .none: color = .none
            case .custom: if case .custom = color {} else { color = .custom(RGBAColor(WidgetPalette.threshold(level))) }
            }
        }
    }

    private var swiftUIColor: Binding<Color> {
        Binding {
            switch color {
            case .custom(let rgba): return Color(nsColor: rgba.nsColor)
            // Renksiz: menü çubuğundaki gibi etiket rengi görünsün (yeşil kalıp yanıltmasın).
            case .none: return Color(nsColor: .labelColor)
            case .automatic: return Color(nsColor: WidgetPalette.threshold(level))
            }
        } set: {
            color = .custom(RGBAColor(NSColor($0)))
        }
    }

    var body: some View {
        LabeledContent("\(level.displayName) rengi") {
            HStack(spacing: 8) {
                Picker("\(level.displayName) rengi", selection: choice) {
                    Text("Varsayılan (\(defaultName))").tag(Choice.automatic)
                    Text("Renksiz").tag(Choice.none)
                    Text("Özel").tag(Choice.custom)
                }
                .labelsHidden()
                .fixedSize()
                ColorPicker("\(level.displayName) özel rengi", selection: swiftUIColor, supportsOpacity: false)
                    .labelsHidden()
                    .opacity(choice.wrappedValue == .custom ? 1 : 0.4)
                    .help("Özel renk seç")
            }
        }
        .help("Renksiz: menü çubuğunun yazı rengi (açık/koyu görünüme uyar).")
    }
}
