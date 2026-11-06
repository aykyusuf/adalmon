import SwiftUI

/// Ana pencerede bir Ayarlar bölümü: diğer sayfalarla aynı başlık, altında gruplu form içeriği.
struct SettingsPage<Content: View>: View {
    let section: SettingsSection
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: section.title)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 4)
            content
        }
    }
}
