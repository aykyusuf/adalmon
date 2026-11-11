import AVFoundation
import QuartzCore

/// Videonun ekrana oturması: "Doldur" kırpar (varsayılan), "Sığdır" kırpmadan siyah bar bırakır.
/// Ana uygulama ve ekran koruyucu aynı eşlemeyi kullanır (ekran koruyucuya oynatma listesi JSON'uyla gider).
enum LoopFit: String, Codable, CaseIterable, Identifiable, Sendable {
    case fill
    case fit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: "Doldur"
        case .fit: "Sığdır"
        }
    }

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill: .resizeAspectFill
        case .fit: .resizeAspect
        }
    }

    /// Poster / sabit görüntü katmanı için karşılığı (video ile aynı oturmalı).
    var contentsGravity: CALayerContentsGravity {
        switch self {
        case .fill: .resizeAspectFill
        case .fit: .resizeAspect
        }
    }
}
