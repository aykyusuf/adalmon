import CoreGraphics
import Foundation

/// Vektör tema: aynı odadaki ad etiketlerinin (hap) çakışma çözümü. Saf mantık (SpriteKit'siz, deterministik).
/// Sıra: (1) soldan sağa yerleştirirken çakışan etiket dikeyde en çok `maxLevel` kademe yukarı alınır;
/// (2) bu yetmezse tüm odanın etiketleri bir sonraki metin biçimine geçer (tam ad → önek atılmış → 14 karakter "…");
/// (3) son biçimde de sığmayan etiket: öncelikli (`priority >= protectedPriority`, ör. oturum) ise en az çakışan kademeye konur
/// (kabul edilen çakışma; `overlaps` sayar), değilse gizlenir (`hidden`; üst üste binmez). Öncelik sırası: oturum > çalışan alt ajan > boşta.
/// Maliyet: en çok 3 aşama × etiket × 3 kademe × yerleşmiş etiket (odada ≲ 15 etiket); olay/zoom değişmedikçe yeniden çalışmaz.
struct OfficeLabelItem: Equatable {
    var id: String
    /// Dünya birimi: etiket merkez x'i ve kademe 0'daki alt y'si.
    var x: CGFloat
    var y: CGFloat
    /// Metin biçimlerinin ekran piksel genişlikleri (0: tam ad, sonra giderek kısalan).
    var widths: [CGFloat]
    /// Büyük = önemli (önce yerleşir, sığmazsa en son gizlenir). Varsayılan: gizlenmez.
    var priority: Int = OfficeLabelLayout.protectedPriority
}

struct OfficeLabelPlacement: Equatable {
    var variant: Int
    var level: Int
    /// Hiçbir kademeye sığmadı ve önceliği düşük: etiket çizilmez (tooltip/kart yine ad söyler).
    var hidden = false
}

enum OfficeLabelLayout {
    /// Hap görünür yüksekliği ve kademe adımı (ekran pikseli).
    static let height: CGFloat = 16
    static let step: CGFloat = 16
    static let maxLevel = 2
    static let margin: CGFloat = 2
    static let shortLimit = 14
    /// Oturum etiketi (gizlenmez) / çalışan alt ajan / boşta alt ajan.
    static let protectedPriority = 2
    static let runningPriority = 1
    static let idlePriority = 0

    /// Etiket metin biçimleri: tam ad; `eklenti:` öneki atılmış ad; en çok 14 karakter "…" ile kısaltılmış ad (yinelenenler elenir).
    static func variants(of title: String) -> [String] {
        var out = [title]
        let stripped = title.contains(":") && !title.hasPrefix("★") ? String(title[title.index(after: title.lastIndex(of: ":")!)...]) : title
        if !stripped.isEmpty, !out.contains(stripped) { out.append(stripped) }
        let short = stripped.count <= shortLimit ? stripped : String(stripped.prefix(shortLimit - 1)) + "…"
        if !out.contains(short) { out.append(short) }
        return out
    }

    static func rect(_ item: OfficeLabelItem, variant: Int, level: Int, zoom z: CGFloat) -> CGRect {
        let w = item.widths[min(variant, item.widths.count - 1)]
        return CGRect(x: item.x - (w + margin) / 2 / z, y: item.y + CGFloat(level) * step / z, width: (w + margin) / z, height: height / z)
    }

    /// Her etiket için biçim + kademe. `overlaps`: çözülemeyip kabul edilen çakışan çift sayısı.
    static func resolve(_ items: [OfficeLabelItem], zoom: CGFloat) -> (placements: [String: OfficeLabelPlacement], overlaps: Int) {
        let z = max(zoom, 0.01)
        let sorted = items.filter { !$0.widths.isEmpty }.sorted {
            $0.priority != $1.priority ? $0.priority > $1.priority : ($0.x, $0.y, $0.id) < ($1.x, $1.y, $1.id)
        }
        guard !sorted.isEmpty else { return ([:], 0) }
        let stages = sorted.map(\.widths.count).max() ?? 1
        var result: [String: OfficeLabelPlacement] = [:]
        for stage in 0..<stages {
            let last = stage == stages - 1
            var placed: [CGRect] = []
            var out: [String: OfficeLabelPlacement] = [:]
            var failed = false
            for item in sorted {
                let variant = min(stage, item.widths.count - 1)
                var chosen: Int?
                for level in 0...maxLevel {
                    let r = rect(item, variant: variant, level: level, zoom: z)
                    if !placed.contains(where: { $0.intersects(r) }) { chosen = level; break }
                }
                if chosen == nil {
                    failed = true
                    if !last { break }
                    if item.priority < protectedPriority {
                        out[item.id] = OfficeLabelPlacement(variant: variant, level: 0, hidden: true)
                        continue
                    }
                    // Kabul edilen çakışma: en az kesişim alanı, eşitlikte en düşük kademe.
                    var best = (level: 0, area: CGFloat.greatestFiniteMagnitude)
                    for level in 0...maxLevel {
                        let r = rect(item, variant: variant, level: level, zoom: z)
                        let area = placed.reduce(CGFloat(0)) { acc, p in p.intersects(r) ? acc + p.intersection(r).width * p.intersection(r).height : acc }
                        if area < best.area - 0.0001 { best = (level, area) }
                    }
                    chosen = best.level
                }
                let level = chosen ?? 0
                out[item.id] = OfficeLabelPlacement(variant: variant, level: level)
                placed.append(rect(item, variant: variant, level: level, zoom: z))
            }
            if !failed || last { result = out }
            if !failed { break }
        }
        return (result, overlapCount(sorted, result, zoom: z))
    }

    static func overlapCount(_ items: [OfficeLabelItem], _ placements: [String: OfficeLabelPlacement], zoom z: CGFloat) -> Int {
        let rects = items.compactMap { i in placements[i.id].flatMap { $0.hidden ? nil : $0 }.map { rect(i, variant: $0.variant, level: $0.level, zoom: z) } }
        var n = 0
        for i in rects.indices { for j in rects.indices where j > i && rects[i].intersects(rects[j]) { n += 1 } }
        return n
    }
}
