import SwiftUI

/// Mobil / Wi-Fi ve diğer renkleri; grafikler ve göstergeler aynı eşlemeyi kullanır.
enum AppUsageSeries {
    static let mobile = "Mobil"
    static let other = "Wi-Fi ve diğer"
    static let scaleDomain = [other, mobile]
    static let scaleRange: [Color] = [.blue, .orange]
}
