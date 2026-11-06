import SwiftUI

/// Mobil veri sayfasındaki kart: başlık satırı (+ isteğe bağlı sağ bileşen) ve içerik.
struct MobileCard<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                accessory
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
    }
}

extension MobileCard where Accessory == EmptyView {
    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, systemImage: systemImage, accessory: { EmptyView() }, content: content)
    }
}
