import SwiftUI

/// Bakım: yalnızca bilgi + kopyala. Hiçbir komut çalıştırılmaz (yönetici gerektirenler Terminal'de elle çalıştırılır).
struct MaintenanceSection: View {
    private let accent = CleanupAccent.maintenance

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                ForEach(MaintenanceInfo.topics) { MaintenanceTopicCard(topic: $0, accent: accent) }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }

    private var hero: some View {
        HStack(spacing: 18) {
            CleanupHeroArtwork(symbol: "wrench.and.screwdriver.fill", accent: accent, size: 92)
                .frame(width: 124, height: 124)
            VStack(alignment: .leading, spacing: 8) {
                Text("Bakım").font(.largeTitle.weight(.bold))
                Text("Bazı bakım işleri yönetici izni ister. Adalmon bunları sizin yerinize çalıştırmaz; komutu kopyalayıp Terminal'e yapıştırırsınız.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Label(MaintenanceInfo.terminalNote, systemImage: "terminal")
                    .font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}
