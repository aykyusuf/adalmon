import AppKit

/// Menü çubuğu paneli. Kenarlıksız `NSPanel` varsayılan olarak anahtar pencere olamaz; bu yüzden Esc tuşu hiç
/// ulaşmazdı. Etkinleştirmeden (`nonactivatingPanel`) anahtar olabilir ve Esc'i (`cancelOperation`) kapatma olarak yollar.
final class PanelWindow: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Esc, SwiftUI içeriği olayı yutsa bile pencere düzeyinde yakalanır (cancelOperation her zaman çağrılmıyor).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onCancel?()
            return
        }
        super.sendEvent(event)
    }
}
