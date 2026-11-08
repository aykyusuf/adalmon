import CoreGraphics
import Foundation

// Ajan ofisi: oda ızgarası yerleşimi ve kamera hesabı. Saf (SpriteKit'siz); içerik koordinatı sol-üst başlangıçlı, y aşağı.

struct OfficeRoomSize: Equatable, Sendable {
    var id: String
    var width: Double
    var height: Double
}

struct OfficeRoomCell: Equatable, Sendable {
    var id: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct OfficeRoomArrangement: Equatable, Sendable {
    var cells: [OfficeRoomCell]
    var columns: Int
    var contentWidth: Double
    var contentHeight: Double
    /// Pencereye sığdıran tamsayı yakınlaştırma (en az 1); `best` doldurur.
    var zoom: Int = 1

    var contentSize: CGSize { CGSize(width: contentWidth, height: contentHeight) }
    func cell(id: String) -> OfficeRoomCell? { cells.first { $0.id == id } }
    func cell(at p: CGPoint) -> OfficeRoomCell? { cells.first { $0.rect.contains(p) } }
}

enum OfficeRoomArranger {
    /// Odalar arası koridor ve dış kenar boşluğu (dünya birimi = 1 piksel, zoom 1'de).
    static let gap = 20.0
    static let margin = 10.0

    /// Odalar sırayla satır satır, `columns` sütunlu ızgaraya dizilir. Sütun genişliği o sütunun en genişi, satır yüksekliği
    /// o satırın en yükseğidir; odalar hücrelerinin sol-üstüne yaslanır.
    static func arrange(_ sizes: [OfficeRoomSize], columns requested: Int) -> OfficeRoomArrangement {
        guard !sizes.isEmpty else { return OfficeRoomArrangement(cells: [], columns: 0, contentWidth: margin * 2, contentHeight: margin * 2) }
        let columns = max(1, min(requested, sizes.count))
        let rowCount = (sizes.count + columns - 1) / columns
        var colW = [Double](repeating: 0, count: columns)
        var rowH = [Double](repeating: 0, count: rowCount)
        for (i, s) in sizes.enumerated() {
            colW[i % columns] = max(colW[i % columns], s.width)
            rowH[i / columns] = max(rowH[i / columns], s.height)
        }
        var colX = [Double](repeating: margin, count: columns)
        for c in 1..<max(columns, 1) { colX[c] = colX[c - 1] + colW[c - 1] + gap }
        var rowY = [Double](repeating: margin, count: rowCount)
        for r in 1..<max(rowCount, 1) { rowY[r] = rowY[r - 1] + rowH[r - 1] + gap }
        let cells = sizes.enumerated().map { i, s in
            OfficeRoomCell(id: s.id, x: colX[i % columns], y: rowY[i / columns], width: s.width, height: s.height)
        }
        let w = margin * 2 + colW.reduce(0, +) + gap * Double(columns - 1)
        let h = margin * 2 + rowH.reduce(0, +) + gap * Double(rowCount - 1)
        return OfficeRoomArrangement(cells: cells, columns: columns, contentWidth: w, contentHeight: h)
    }

    /// Sütun sayısını pencereye göre seçer: önce en büyük tamsayı zoom, sonra gerçek (kesirli) sığma ölçeği, sonra az sütun.
    /// Zoom 1'de bile sığmıyorsa en az taşan düzen seçilir (sahne kaydırılabilir).
    static func best(_ sizes: [OfficeRoomSize], viewWidth: Double, viewHeight: Double) -> OfficeRoomArrangement {
        guard !sizes.isEmpty else { return arrange(sizes, columns: 1) }
        var best: (arr: OfficeRoomArrangement, fit: Double)?
        for columns in 1...sizes.count {
            var arr = arrange(sizes, columns: columns)
            arr.zoom = OfficeCamera.fitZoom(view: CGSize(width: viewWidth, height: viewHeight), content: arr.contentSize)
            let fit = min(viewWidth / arr.contentWidth, viewHeight / arr.contentHeight)
            if let b = best {
                if (arr.zoom, fit) > (b.arr.zoom, b.fit + 1e-9) { best = (arr, fit) }
            } else {
                best = (arr, fit)
            }
        }
        return best!.arr
    }
}

/// Kamera: tamsayı zoom'a sığdırma, odaya odaklanma, kaydırma sınırı, görünüm ↔ içerik koordinatı.
enum OfficeCamera {
    static let maxZoom = 6

    /// İçeriği pencereye sığdıran en büyük tamsayı zoom (en az 1: büyük sahnede küçülmez, kaydırılır).
    static func fitZoom(view: CGSize, content: CGSize, maxZoom: Int = OfficeCamera.maxZoom) -> Int {
        OfficeAppearance.integerZoom(viewWidth: view.width, viewHeight: view.height, contentWidth: content.width, contentHeight: content.height, maxZoom: maxZoom)
    }

    /// Merkezi içerik sınırlarına kıstırır; içerik o eksende pencereden küçükse ortalar.
    static func clamp(center: CGPoint, content: CGSize, view: CGSize, zoom: Int) -> CGPoint {
        func axis(_ c: Double, _ content: Double, _ view: Double) -> Double {
            let half = view / Double(max(1, zoom)) / 2
            if content <= half * 2 { return content / 2 }
            return min(max(c, half), content - half)
        }
        return CGPoint(x: axis(center.x, content.width, view.width), y: axis(center.y, content.height, view.height))
    }

    /// Bir odaya yakınlaşma: odayı (kenar boşluğuyla) sığdıran zoom ve oda merkezi.
    static func focus(on rect: CGRect, content: CGSize, view: CGSize, margin: Double = 12) -> (zoom: Int, center: CGPoint) {
        let z = fitZoom(view: view, content: CGSize(width: rect.width + margin * 2, height: rect.height + margin * 2))
        let c = clamp(center: CGPoint(x: rect.midX, y: rect.midY), content: content, view: view, zoom: z)
        return (z, c)
    }

    /// Pencerenin içerik koordinatındaki görünen dikdörtgeni.
    static func viewport(center: CGPoint, view: CGSize, zoom: Int) -> CGRect {
        let w = view.width / Double(max(1, zoom)), h = view.height / Double(max(1, zoom))
        return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    }

    /// Görünüm noktası (sol-alt başlangıçlı, y yukarı) → içerik noktası (y aşağı).
    static func contentPoint(fromView p: CGPoint, view: CGSize, center: CGPoint, zoom: Int) -> CGPoint {
        let z = Double(max(1, zoom))
        return CGPoint(x: center.x + (p.x - view.width / 2) / z, y: center.y - (p.y - view.height / 2) / z)
    }
}
