import CoreGraphics
import Foundation

/// `CGWindowListCopyWindowInfo` satırından yalnızca gereken alanlar (Screen Recording izni gerekmez).
struct WindowSnapshot: Equatable, Sendable {
    var layer: Int
    var alpha: Double
    var bounds: CGRect
    var ownerPID: Int32
}

/// Masaüstünün ne kadarı örtülü? Pencereler üst üste binse bile birleşim alanı ölçülür (yan yana dizilmiş pencereler).
enum OcclusionCheck {
    struct Result: Equatable, Sendable {
        /// Ekranın örtülen oranı (0...1).
        var coverage: Double
        /// Tek bir normal pencere menü çubuğu dahil ekranın tamamını kaplıyor.
        var fullScreen: Bool
    }

    static let coveredThreshold = 0.9
    static let fullScreenThreshold = 0.995
    private static let gridX = 48
    private static let gridY = 27

    /// Pencereler z-sırasından bağımsızdır; yalnızca layer 0 (normal uygulama penceresi) ve opak (alpha > 0.99) sayılır.
    /// `excludingPID` kendi pencerelerimizi (ör. masaüstü pencereleri layer < 0 olduğundan zaten dışarıda) ayıklamak içindir.
    static func analyze(windows: [WindowSnapshot], display: CGRect, excludingPID: Int32? = nil) -> Result {
        guard display.width > 0, display.height > 0 else { return Result(coverage: 0, fullScreen: false) }
        let displayArea = Double(display.width * display.height)
        var cells = [Bool](repeating: false, count: gridX * gridY)
        var fullScreen = false
        let cw = display.width / CGFloat(gridX), ch = display.height / CGFloat(gridY)
        for w in windows where w.layer == 0 && w.alpha > 0.99 && w.ownerPID != excludingPID {
            let r = w.bounds.intersection(display)
            guard !r.isNull, r.width > 0, r.height > 0 else { continue }
            if Double(r.width * r.height) / displayArea >= fullScreenThreshold { fullScreen = true }
            // Hücrenin MERKEZİ pencerenin içindeyse hücre örtülü sayılır (kenarlarda en çok yarım hücre hatası).
            let x0 = max(0, Int(((r.minX - display.minX) / cw - 0.5).rounded(.up)))
            let x1 = min(gridX - 1, Int(((r.maxX - display.minX) / cw - 0.5).rounded(.down)))
            let y0 = max(0, Int(((r.minY - display.minY) / ch - 0.5).rounded(.up)))
            let y1 = min(gridY - 1, Int(((r.maxY - display.minY) / ch - 0.5).rounded(.down)))
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 { for x in x0...x1 { cells[y * gridX + x] = true } }
        }
        let covered = cells.reduce(0) { $0 + ($1 ? 1 : 0) }
        return Result(coverage: Double(covered) / Double(cells.count), fullScreen: fullScreen)
    }

    static func isCovered(_ result: Result) -> Bool { result.coverage >= coveredThreshold || result.fullScreen }

    /// Canlı pencere listesi (yalnızca ekrandaki pencereler, masaüstü öğeleri hariç).
    static func liveWindows() -> [WindowSnapshot] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var out: [WindowSnapshot] = []
        out.reserveCapacity(list.count)
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            out.append(WindowSnapshot(layer: layer, alpha: (w[kCGWindowAlpha as String] as? Double) ?? 1, bounds: bounds,
                                      ownerPID: Int32(truncatingIfNeeded: (w[kCGWindowOwnerPID as String] as? Int) ?? 0)))
        }
        return out
    }
}
