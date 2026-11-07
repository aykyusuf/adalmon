import SwiftUI

/// İçeriği, sunulan boyuta zorla sığdırır: içeriğin kendi (ideal/en az) yüksekliği ne olursa olsun üst görünüme
/// bildirilen boyut sunulan boyutu aşmaz. NavigationSplitView içindeki kaydırılabilir tablolar çok satırda yüksekliğini
/// içeriğe göre bildirip tüm pencereyi (kenar çubuğu dahil) pencere dışına itiyordu.
struct BoundedHeight<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            content.frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
