import SwiftUI

/// Kenar çubuğu: sayfalar, ardından Ayarlar bölümleri.
struct MainSidebar: View {
    @Binding var selection: MainSection?

    var body: some View {
        List(selection: $selection) {
            ForEach(MainSection.pages) { SidebarRow(section: $0) }
            Section("Ayarlar") {
                ForEach(MainSection.dockSettingsSections) { SidebarRow(section: .settings($0)) }
            }
        }
    }
}
