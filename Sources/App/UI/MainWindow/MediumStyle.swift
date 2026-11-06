import SwiftUI

/// Mobil ve Wi-Fi/diğer ayrımının renkleri: tablolardaki "Mobil" (turuncu) ile tutarlı; indirme (mavi) ile karışmaz.
enum MediumStyle {
    static let mobileName = "Mobil"
    static let wifiName = "Wi-Fi"
    static let mobileColor = Color.orange
    static let wifiColor = Color.teal

    /// Grafik açıklaması ve renk eşlemesi için.
    static let scale: KeyValuePairs<String, Color> = [wifiName: wifiColor, mobileName: mobileColor]
}
