import Foundation

/// Panelde gösterilen "en çok kullanan" satırı.
struct TopProcess: Identifiable, Equatable {
    var key: String
    var name: String
    /// "%12", "1,2 GB".
    var valueText: String
    /// 0...1: listedeki en büyük değere göre çubuk.
    var fraction: Double
    var id: String { key }
}

/// Canlı süreç örneğinden ilk N uygulamayı çıkaran saf hesap.
enum TopProcessBuilder {
    enum Metric: Equatable { case cpu, gpu, memory }

    static func top(_ snapshot: LiveSnapshot, metric: Metric, cores: Int, limit: Int = 5,
                    name: (String) -> String) -> [TopProcess] {
        guard snapshot.elapsed > 0 else { return [] }
        var rows: [(key: String, value: Double)] = []
        for group in snapshot.groups where !ResourceKeys.isSpecial(group.key) {
            let rates = LiveRow.Rates(usage: group.usage, elapsed: snapshot.elapsed, cores: cores)
            switch metric {
            case .cpu where rates.cpu >= 0.05: rows.append((group.key, rates.cpu))
            case .gpu where rates.gpu >= 0.05: rows.append((group.key, rates.gpu))
            case .memory where group.usage.footprint > 0: rows.append((group.key, Double(group.usage.footprint)))
            default: break
            }
        }
        rows.sort { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let top = Array(rows.prefix(limit))
        // Çubuk ölçeği: yüzdelerde en az %10, bellekte en büyük değer.
        let scale = max(top.first?.value ?? 1, metric == .memory ? 1 : 10)
        return top.map { row in
            let text: String = switch metric {
            case .cpu, .gpu: row.value < 10 ? "%" + row.value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "tr_TR")))
                : "%\(Int(row.value.rounded()))"
            case .memory: ResourceFormat.bytes(row.value)
            }
            return TopProcess(key: row.key, name: name(row.key), valueText: text, fraction: min(1, row.value / scale))
        }
    }

    /// Diskte son 1 saatte en çok yazanlar (`UsageStore.recentTop(.diskWrite)`).
    static func writers(_ ranks: [ResourceRank], name: (String) -> String) -> [TopProcess] {
        let top = ranks.filter { !ResourceKeys.isSpecial($0.app) }.prefix(5)
        let scale = max(top.first?.value ?? 1, 1)
        return top.map { TopProcess(key: $0.app, name: name($0.app), valueText: ResourceFormat.bytes($0.value), fraction: min(1, $0.value / scale)) }
    }
}
