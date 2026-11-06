import SwiftUI

struct SidebarRow: View {
    let section: MainSection

    var body: some View {
        NavigationLink(value: section) {
            Label {
                Text(section.title)
            } icon: {
                SettingsSidebarIcon(symbol: section.symbol, tint: section.tint)
            }
        }
    }
}
