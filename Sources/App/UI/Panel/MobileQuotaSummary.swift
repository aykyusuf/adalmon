import Foundation

/// "Kota" satırının değerleri: bugünkü mobil kullanım, etkin günlük limit ve dolma tahmini.
struct MobileQuotaSummary: Equatable {
    var usedBytes: UInt64
    var capBytes: UInt64
    var eta: CapETA

    init(usedBytes: UInt64, capBytes: UInt64, eta: CapETA = .noData) {
        self.usedBytes = usedBytes
        self.capBytes = capBytes
        self.eta = eta
    }

    init(_ data: PanelData) {
        guard let b = data.budget else {
            self.init(usedBytes: data.mobileToday, capBytes: data.dailyCapBytes)
            return
        }
        // Aylık limit varsa ve dinamik bütçe günlük limitten kısıtlayıcıysa tahmin ona göre.
        let budgetBinds = (b.dynamicDailyBudgetBytes ?? .max) < data.dailyCapBytes
        let eta = budgetBinds ? (b.etaBudgetRecentRate ?? b.etaRecentRate) : b.etaRecentRate
        self.init(usedBytes: data.mobileToday, capBytes: b.effectiveDailyCapBytes, eta: eta)
    }

    var fraction: Double { capBytes == 0 ? 0 : min(1, Double(usedBytes) / Double(capBytes)) }

    /// Limit doldu ya da bugün dolacağı tahmin ediliyor.
    var isUrgent: Bool {
        switch eta {
        case .reached, .at: true
        case .notToday, .noData: false
        }
    }

    var percentText: String { Format.percent(fraction) }

    var level: Level { fraction >= 1 ? .critical : (fraction >= 0.8 ? .warning : .normal) }

    enum Level { case normal, warning, critical }

    /// "21:40 civarı dolar", "Limit doldu"; tahmin yoksa nil.
    func etaText(locale: Locale = Locale(identifier: "tr_TR")) -> String? {
        switch eta {
        case .reached:
            return "Limit doldu"
        case .at(let date):
            let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
            return "\(time) civarı dolar"
        case .notToday, .noData:
            return nil
        }
    }

    private static let capFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
        .locale(Locale(identifier: "tr_TR"))
    private static let usedFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        .locale(Locale(identifier: "tr_TR"))

    /// "1,24 / 3 GB" (aynı birimde, kısa).
    var usageText: String {
        let used = Double(usedBytes) / 1_000_000_000
        let cap = Double(capBytes) / 1_000_000_000
        if cap >= 1 || used >= 1 {
            return "\(used.formatted(Self.usedFormat)) / \(cap.formatted(Self.capFormat)) GB"
        }
        return "\(Format.bytes(usedBytes)) / \(Format.bytes(capBytes))"
    }
}
