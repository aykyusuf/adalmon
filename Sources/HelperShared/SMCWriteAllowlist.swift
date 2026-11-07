import Foundation

/// Yardımcının SMC'ye yazabileceği tüm (anahtar, değer) çiftleri. Keyfi yazma yoktur.
enum SMCWriteAllowlist {
    /// "şarjı durdur" / "şarja izin ver" yazımları.
    static func inhibitWrites(method: ChargeInhibitMethod, inhibited: Bool) -> [SMCWrite] {
        switch method {
        case .chte: [SMCWrite(key: .chte, bytes: inhibited ? [1, 0, 0, 0] : [0, 0, 0, 0])]
        case .ch0bc: [SMCWrite(key: .ch0b, bytes: [inhibited ? 2 : 0]), SMCWrite(key: .ch0c, bytes: [inhibited ? 2 : 0])]
        }
    }

    /// MagSafe LED baytları (battery CLI eşlemesi: 0 otomatik, 1 kapalı, 3 yeşil, 4 turuncu).
    /// DİKKAT: bu eşleme bu Mac'te doğrulanmadı; arayüz "deneysel" der.
    static func ledWrite(_ mode: MagSafeLEDMode) -> SMCWrite {
        let byte: UInt8 = switch mode {
        case .auto: 0
        case .off: 1
        case .green: 3
        case .orange: 4
        }
        return SMCWrite(key: .aclc, bytes: [byte])
    }

    static func permits(_ write: SMCWrite) -> Bool {
        switch write.key {
        case .chte: write.bytes == [1, 0, 0, 0] || write.bytes == [0, 0, 0, 0]
        case .ch0b, .ch0c: write.bytes == [2] || write.bytes == [0]
        case .aclc: write.bytes.count == 1 && [0, 1, 3, 4].contains(write.bytes[0])
        }
    }
}
