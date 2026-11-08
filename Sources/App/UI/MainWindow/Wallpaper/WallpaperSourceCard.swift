import SwiftUI

/// Kaynak seçimi: Video (kütüphane) ya da Ajan ofisi (canlı sahne). Aynı anda yalnızca biri çalışır.
struct WallpaperSourceCard: View {
    @Bindable var service: WallpaperService

    var body: some View {
        RulesCard(title: "Kaynak", systemImage: "rectangle.on.rectangle",
                  subtitle: "Aynı anda yalnızca biri çalışır; kaynak değişince diğeri tamamen durur.") {
            Picker("Kaynak", selection: $service.settings.source) {
                ForEach(WallpaperSource.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .accessibilityLabel("Duvar kâğıdı kaynağı")
        }
    }
}

/// Ofis kaynağının ayarları: ışık, tema, arka plan, etiketler. Duvar kâğıdı fareyi almaz; etkileşim yalnızca uygulama penceresinde.
struct WallpaperOfficeCard: View {
    @Bindable var service: WallpaperService
    var agentsEnabled: Bool = true
    var openAgents: () -> Void = {}
    @AppStorage(OfficeTheme.defaultsKey) private var themeRaw = OfficeTheme.default.rawValue

    var body: some View {
        RulesCard(title: "Ajan ofisi", systemImage: "building.2",
                  subtitle: "Canlı Claude oturumları masaüstünde; tüm odalar ekrana sığar. Tıklama ve üzerine gelme yoktur, etkileşim için ofis penceresini açın.") {
            if !agentsEnabled {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("Claude ajanları özelliği kapalı: önce açın", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                    Spacer(minLength: 8)
                    Button("Özelliği aç", action: openAgents)
                }
                Text("Kapalıyken duvar kâğıdı boş bir oda gösterir.").font(.caption).foregroundStyle(.secondary)
            }
            picker("Işık", selection: $service.settings.office.lighting, options: OfficeLightingMode.allCases.map { ($0, $0.title) },
                   help: "Otomatik: yerel saate göre gece 19:30–06:30.")
            Picker("Tema", selection: $themeRaw) {
                ForEach(OfficeTheme.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 360)
            picker("Arka plan", selection: $service.settings.office.background, options: OfficeWallpaperBackground.allCases.map { ($0, $0.title) },
                   help: "Odaların dışındaki zemin.")
            picker("Etiketleri göster", selection: $service.settings.office.labels, options: OfficeLabelPolicy.allCases.map { ($0, $0.title) },
                   help: "Otomatik: ekran küçükse ya da çok oda varsa karakter etiketleri gizlenir.")
            Divider()
            Text("Pil: sahne 10 kare/sn çizilir; ajan yokken ya da hepsi boştayken çizim durur. Pildeyken, Düşük Güç Modunda, masaüstü görünmüyorken ve diğer duraklatma kurallarında sahne durur, son kare kalır.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func picker<T: Hashable>(_ title: String, selection: Binding<T>, options: [(T, String)], help: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker(title, selection: selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 360)
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }
}
