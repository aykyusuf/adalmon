import Foundation
import Observation

/// Açık panelin değişken durumu. Tek `NSHostingView` açık kalır; içerik türü buradan değişir (titreme yok).
@MainActor @Observable
final class PanelSession {
    var kind: PanelKind = .combined
    /// Menü çubuğundaki cihaz öğesinden açıldıysa o cihaz (pil paneli ona kaydırılır).
    var focusDeviceID: String?
    /// Panelin alabileceği en büyük yükseklik (ekrana göre).
    var maxHeight: CGFloat = 640
}
