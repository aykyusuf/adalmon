import SwiftUI

/// Simgesi renkli, başlığı çevresinden devralan etiket stili (kart ve kota başlıkları).
struct PanelTitleLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}
