import AppKit

/// Menü çubuğu paneli. Kenarlıksız `NSPanel` varsayılan olarak anahtar pencere olamaz; bu yüzden Esc tuşu hiç
/// ulaşmazdı. Etkinleştirmeden (`nonactivatingPanel`) anahtar olabilir ve Esc'i (`cancelOperation`) kapatma olarak yollar.
final class PanelWindow: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
