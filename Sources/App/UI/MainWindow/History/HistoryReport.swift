import Foundation

/// Bir dönemin kısa ağ raporu: toplam, mobil/Wi-Fi, önceki dönemle kıyas, en çok kullanan uygulama ve alan adları.
struct HistoryReport: Equatable, Sendable {
    var period: HistoryReportPeriod
    var mobile: UInt64
    var other: UInt64
    /// Önceki aynı uzunluktaki dönemin toplamı (0 = kayıt yok).
    var previousTotal: UInt64
    var apps: [HistoryAppBytes]
    var domains: [HistoryDomainBytes]
    /// Uygulamalara atfedilen toplam (günlük uygulama tablosu); arayüz toplamından düşük olabilir.
    var attributed: UInt64

    var total: UInt64 { mobile + other }
    var isEmpty: Bool { total == 0 && apps.isEmpty }

    /// Mobilin toplamdaki payı, 0...1.
    var mobileShare: Double { total > 0 ? Double(mobile) / Double(total) : 0 }

    /// Çok günlük dönemlerde günlük ortalama.
    var dailyAverage: UInt64? { period.dayCount > 1 && total > 0 ? total / UInt64(period.dayCount) : nil }

    /// Önceki döneme göre değişim (+0,12 = %12 artış). Karşılaştırma yoksa nil.
    var changeFraction: Double? {
        guard period.isComparable, previousTotal > 0 else { return nil }
        return (Double(total) - Double(previousTotal)) / Double(previousTotal)
    }

    /// "+%12", "-%5", "%0".
    var changeText: String? {
        guard let f = changeFraction else { return nil }
        let pct = Int((abs(f) * 100).rounded())
        if pct == 0 { return "%0" }
        return (f > 0 ? "+" : "-") + "%\(pct)"
    }

    /// Uygulama dökümü toplamın ne kadarını açıklıyor (0...1); toplam yoksa nil.
    var attributedFraction: Double? {
        total > 0 ? min(1, Double(attributed) / Double(total)) : nil
    }

    /// Panoya kopyalanacak kısa düz metin. `appName`, uygulama yolunu gösterim adına çevirir.
    func summaryText(appName: (String) -> String) -> String {
        var lines: [String] = []
        lines.append("Adalmon ağ raporu: \(period.title) (\(period.subtitle))")
        var totalLine = "Toplam: \(Format.bytes(total))"
        if let text = changeText {
            totalLine += " (önceki dönem \(Format.bytes(previousTotal)), \(text))"
        } else if previousTotal > 0 {
            totalLine += " (dün: \(Format.bytes(previousTotal)))"
        }
        lines.append(totalLine)
        lines.append("\(MediumStyle.mobileName): \(Format.bytes(mobile)) · \(MediumStyle.wifiName)/diğer: \(Format.bytes(other))")
        if let avg = dailyAverage { lines.append("Günlük ortalama: \(Format.bytes(avg))") }
        if !apps.isEmpty {
            lines.append("")
            lines.append("En çok kullanan uygulamalar:")
            for (i, app) in apps.enumerated() { lines.append("\(i + 1). \(appName(app.app)): \(Format.bytes(app.bytes))") }
        }
        if !domains.isEmpty {
            lines.append("")
            lines.append("En çok kullanılan alan adları:")
            for (i, d) in domains.enumerated() { lines.append("\(i + 1). \(d.name): \(Format.bytes(d.bytes))") }
        }
        return lines.joined(separator: "\n")
    }
}
