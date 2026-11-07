import Foundation

/// Bluetooth SIG Battery Service (0x180F) / Battery Level (0x2A19) değer çözümleyicisi.
enum GATTBattery {
    static let serviceUUID = "180F"
    static let levelUUID = "2A19"

    /// Tek bayt, 0…100. Aksi halde nil.
    static func parseLevel(_ data: Data) -> Int? {
        guard let first = data.first, first <= 100 else { return nil }
        return Int(first)
    }
}
