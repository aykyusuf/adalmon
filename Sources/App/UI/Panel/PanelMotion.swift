import SwiftUI

/// Hareketi azalt ayarına saygı duyan animasyon yardımcıları (panelde sürekli animasyon yoktur).
extension Animation {
    /// Panel geçişleri için `.snappy`; hareketi azalt açıksa nil (anında).
    static func panel(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .snappy }
}
