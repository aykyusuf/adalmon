import Foundation
import Observation

/// Açık panelin değişken durumu. Tek `NSHostingView` açık kalır; içerik türü buradan değişir (titreme yok).
@MainActor @Observable
final class PanelSession {
    var kind: PanelKind = .combined
    /// Panelin alabileceği en büyük yükseklik (ekrana göre).
    var maxHeight: CGFloat = 640
}
