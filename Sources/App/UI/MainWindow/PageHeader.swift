import SwiftUI

/// Bölüm sayfalarının büyük başlığı ve isteğe bağlı sağ tarafı. Her zaman tek satır: yer yetmezse
/// sağ taraf başlığın altına iner, başlık hiçbir zaman satır atlamaz.
struct PageHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titleText
                Spacer(minLength: 12)
                accessory.lineLimit(1).fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                titleText
                accessory.lineLimit(1)
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.largeTitle.weight(.bold))
            .lineLimit(1)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }
}

extension PageHeader where Accessory == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}
