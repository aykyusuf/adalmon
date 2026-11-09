import CoreGraphics
import Foundation

/// Pano (kiosk) modu yerleşimi: tam ekranda odalar boş alanı doldurur. Saf mantık (SpriteKit'siz); içerik koordinatı sol-üst başlangıçlı.
/// İçerik boyutu = görünüm / zoom (kenar boşlukları ve eşit aralık içeride), bu yüzden kamera içeriği tam sığdırır, siyah boşluk kalmaz
/// (kalan alanı arka plan doldurur). Kesirli zoom (vektör tema).
enum OfficePanoLayout {
    /// Görünümün kenarlarında bırakılan boşluk oranı (yatay %2, dikey %3).
    static let insetX = 0.02
    static let insetY = 0.03
    /// Sütun sayısı seçiminde odalar arası asgari aralık (dünya birimi).
    static let minGap = OfficeRoomArranger.gap

    /// Etiket/levha/balon büyütmesi: ekran yüksekliğine (nokta) oranla, 900 pt'ye kadar 1, en çok 2.
    static func uiScale(viewHeight: Double) -> Double { min(2, max(1, viewHeight / 900)) }

    struct Result: Equatable {
        var arrangement: OfficeRoomArrangement
        var zoom: Double
    }

    /// Satır satır dizilim için `columns` sütun: her satır en çok `columns` oda; hücreler yerleştirilmeden yalnızca ham boyut (boşluksuz).
    private static func rows(_ sizes: [OfficeRoomSize], columns: Int) -> [[OfficeRoomSize]] {
        stride(from: 0, to: sizes.count, by: columns).map { Array(sizes[$0..<min($0 + columns, sizes.count)]) }
    }

    private static func rawSize(_ rows: [[OfficeRoomSize]]) -> (w: Double, h: Double) {
        let w = rows.map { $0.reduce(0) { $0 + $1.width } + minGap * Double($0.count - 1) }.max() ?? 0
        let h = rows.reduce(0) { $0 + ($1.map(\.height).max() ?? 0) } + minGap * Double(max(0, rows.count - 1))
        return (w, h)
    }

    /// Kesirli sığma zoom'u (en az 1, en çok `maxZoom`): kenar boşlukları görünüm oranı olarak düşülür.
    static func fitZoom(raw: (w: Double, h: Double), view: CGSize, maxZoom: Double = OfficeCamera.maxVectorZoom) -> Double {
        guard raw.w > 0, raw.h > 0, view.width > 0, view.height > 0 else { return 1 }
        let z = min(view.width * (1 - 2 * insetX) / raw.w, view.height * (1 - 2 * insetY) / raw.h)
        return min(maxZoom, max(1, z))
    }

    /// En büyük zoom'u veren sütun sayısını seçer (eşitlikte az sütun), odaları yatayda eşit aralıkla, dikeyde ortalı dizer.
    static func arrange(_ sizes: [OfficeRoomSize], view: CGSize) -> Result {
        guard !sizes.isEmpty, view.width > 0, view.height > 0 else { return Result(arrangement: OfficeRoomArranger.arrange(sizes, columns: 1), zoom: 1) }
        var best: (columns: Int, zoom: Double)?
        for columns in 1...sizes.count {
            let z = fitZoom(raw: rawSize(rows(sizes, columns: columns)), view: view)
            if best == nil || z > best!.zoom + 1e-9 { best = (columns, z) }
        }
        let z = best!.zoom
        let rs = rows(sizes, columns: best!.columns)
        let vw = view.width / z, vh = view.height / z
        let mx = insetX * vw, my = insetY * vh
        let raw = rawSize(rs)
        // Yatay: en kalabalık satıra göre eşit aralık (kenarlar dahil k+1 boşluk); az odalı satırlar aynı aralıkla ortalanır.
        let kMax = rs.map(\.count).max() ?? 1
        let widest = rs.map { $0.reduce(0) { $0 + $1.width } }.max() ?? 0
        // Kenar boşlukları da aynı aralığa eşit (k+1 eşit boşluk); bu kenar boşluğundan (%2) küçük kalacaksa kenarlar mx'te sabitlenir.
        var gapX = minGap
        if kMax > 1 {
            gapX = (vw - widest) / Double(kMax + 1)
            if gapX < mx { gapX = (vw - 2 * mx - widest) / Double(kMax - 1) }
            gapX = max(minGap, gapX)
        }
        // Dikey: odalar ortalanır; birden çok satırda aralık serbest alana göre (en az minGap).
        let rowH = rs.map { $0.map(\.height).max() ?? 0 }
        let freeY = vh - 2 * my - rowH.reduce(0, +)
        let gapY = rs.count > 1 ? max(minGap, freeY / Double(rs.count + 1)) : 0
        let usedY = rowH.reduce(0, +) + gapY * Double(rs.count - 1)
        var y = my + max(0, (vh - 2 * my - usedY) / 2)
        var cells: [OfficeRoomCell] = []
        for (r, row) in rs.enumerated() {
            let rowW = row.reduce(0) { $0 + $1.width } + gapX * Double(row.count - 1)
            var x = max(mx, (vw - rowW) / 2)
            for s in row {
                cells.append(OfficeRoomCell(id: s.id, x: x, y: y, width: s.width, height: s.height))
                x += s.width + gapX
            }
            y += rowH[r] + gapY
        }
        let contentW = max(vw, raw.w + 2 * mx), contentH = max(vh, raw.h + 2 * my)
        let arr = OfficeRoomArrangement(cells: cells, columns: best!.columns, contentWidth: contentW, contentHeight: contentH, zoom: Int(z))
        return Result(arrangement: arr, zoom: z)
    }
}
