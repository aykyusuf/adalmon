import SwiftUI

/// Oynatma: döngüde baştan atla / sondan kes ve geçiş. Ekran koruyucu da aynı değerleri kullanır.
struct WallpaperPlaybackCard: View {
    @Bindable var service: WallpaperService

    var body: some View {
        RulesCard(title: "Oynatma", systemImage: "repeat",
                  subtitle: "Video başa sararken ya da sıradakine geçerken \"pat\" diye atlamasın. Ekran koruyucu aynı ayarları kullanır.") {
            secondsSlider("Baştan atla", value: $service.settings.loop.trimStart, range: LoopTiming.trimLimit, step: 1)
            secondsSlider("Sondan kes", value: $service.settings.loop.trimEnd, range: LoopTiming.trimLimit, step: 1)
            Text("İndirilen videoların başı ve sonu çoğu zaman siyah, kararmalı ya da filigranlıdır. Yalnızca aradaki bölüm döngüye girer. Süre, kırpmalar + 10 sn'den kısa olan videolarda kırpma uygulanmaz.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Picker("Video sığdırma", selection: $service.settings.loop.fit) {
                ForEach(LoopFit.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            Text("Doldur ekranı kaplar, kenarları kırpabilir; Sığdır videoyu kırpmadan gösterir, kalan yerler siyah olur.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Picker("Geçiş", selection: $service.settings.loop.transition) {
                ForEach(LoopTransition.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            if service.settings.loop.transition == .crossfade {
                secondsSlider("Geçiş süresi", value: $service.settings.loop.crossfadeSeconds, range: LoopTiming.crossfadeLimit, step: 0.1)
            }
            Text(footnote).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footnote: String {
        switch service.settings.loop.transition {
        case .crossfade:
            "Geçiş sırasında kısa süre iki video birlikte çözülür; geri kalan zaman tek video çalışır. \"Hareketi Azalt\" açıkken geçiş 0,3 sn'lik kısa bir çözülmeye iner."
        case .off:
            "Geçiş kapalı: tek videoda kırpılan aralık kesintisiz döner, çalma listesinde sıradaki video önceden hazırlanıp sert geçişle başlar."
        }
    }

    private func secondsSlider(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(title).frame(width: 110, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .frame(maxWidth: 280)
                .accessibilityLabel(title)
                .accessibilityValue(Self.label(value.wrappedValue))
            Text(Self.label(value.wrappedValue))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    /// "5 sn", "1,5 sn" (yerel ondalık ayracı).
    static func label(_ seconds: Double) -> String {
        "\(seconds.formatted(.number.precision(.fractionLength(0...1)))) sn"
    }
}
