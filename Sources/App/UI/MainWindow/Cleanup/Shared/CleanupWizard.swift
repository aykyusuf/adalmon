import SwiftUI

// Temizlik tasarım kiti (Shared/): her bölüm aynı 4 adımlı sihirbazı kullanır. Bileşenler genel tutulmuştur:
// içerik closure ile gelir, mantık (tarama / silme) bölümün kendi modelinde kalır; kit yalnızca görünüm ve geçiştir.
//
// Örnek (bir bölümün gövdesi):
//
//     CleanupWizard(step: step) {                       // 1. karşılama
//         CleanupHero3D(symbol: "trash", accent: .junk, title: "Sistem çöpü",
//                       subtitle: "Önbellek ve günlükleri bulalım.", primaryTitle: "Tara") { model.scan() }
//     } scanning: {                                      // 2. tarama
//         CleanupScanProgress(accent: .junk, symbol: "trash", fraction: 0.4, title: "Taranıyor…",
//                             steps: steps) { model.cancel() }
//     } result: {                                        // 3. sonuç
//         VStack(spacing: 0) {
//             ScrollView {
//                 CleanupResultHeader(bytes: found, caption: "temizlenebilir", accent: .junk)
//                 CleanupResultCard(symbol: "folder", title: "Önbellekler", subtitle: "12 öğe", bytes: 3_000_000,
//                                   accent: .junk, selection: .all, onToggle: { ... })
//             }
//             CleanupActionBar(countText: "12 öğe seçili", bytes: selected, mode: $mode, accent: .junk) { confirm() }
//         }
//     } done: {                                          // 4. bitti
//         CleanupDoneView(accent: .junk, bytes: freed) { model.scan() }
//     }
//
// Boş sonuç için `CleanupAllCleanView`. Vurgu rengi: `CleanupSubsection.accent` ya da `CleanupAccent.junk` gibi.
// Pil kuralı: kitte sürekli döngü yoktur; animasyonlar yalnız görünme, hover, adım geçişi ve değer değişiminde çalışır
// ve "Hareketi azalt" ayarına uyar.

/// Sihirbazın adımları. Sıra: karşılama → tarama → sonuç → bitti.
enum CleanupWizardStep: Int, CaseIterable, Comparable, Sendable {
    case welcome, scanning, result, done

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Seçili adımın içeriğini gösterir; adım değişince eski içerik sola kayıp solar, yenisi sağdan gelir (yay, ~0,4 sn).
struct CleanupWizard<Welcome: View, Scanning: View, ResultContent: View, Done: View>: View {
    let step: CleanupWizardStep
    private let welcome: Welcome
    private let scanning: Scanning
    private let result: ResultContent
    private let done: Done
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(step: CleanupWizardStep,
         @ViewBuilder welcome: () -> Welcome,
         @ViewBuilder scanning: () -> Scanning,
         @ViewBuilder result: () -> ResultContent,
         @ViewBuilder done: () -> Done) {
        self.step = step
        self.welcome = welcome()
        self.scanning = scanning()
        self.result = result()
        self.done = done()
    }

    var body: some View {
        ZStack {
            switch step {
            case .welcome: welcome.transition(Self.stepTransition)
            case .scanning: scanning.transition(Self.stepTransition)
            case .result: result.transition(Self.stepTransition)
            case .done: done.transition(Self.stepTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.1), value: step)
    }

    private static var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: WizardShift(x: 36, opacity: 0), identity: WizardShift(x: 0, opacity: 1)),
            removal: .modifier(active: WizardShift(x: -36, opacity: 0), identity: WizardShift(x: 0, opacity: 1))
        )
    }
}

/// Adım geçişi: yatay kayma + solma.
private struct WizardShift: ViewModifier {
    var x: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content.offset(x: x).opacity(opacity)
    }
}
