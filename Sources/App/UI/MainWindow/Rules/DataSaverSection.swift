import SwiftUI

/// Veri Tasarrufu modu: açıkken yalnızca izin listesindeki uygulamalar mobil veri kullanabilir (yalnız mobil / hotspot bağlantısında zorlanır).
struct DataSaverSection: View {
    let model: AppModel
    @Bindable var prefs: Preferences

    var body: some View {
        RulesCard(title: "Veri Tasarrufu", systemImage: "leaf",
                  subtitle: "Açıkken yalnızca izin verdiğin uygulamalar internete çıkar; diğerleri beklemeye alınır.") {
            Toggle("Veri Tasarrufu modu", isOn: $prefs.dataSaver.enabled)
            Label("Yalnızca mobil / hotspot bağlantısında uygulanır; DNS ve sistem hizmetleri her zaman serbesttir.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("İzin listesi").font(.subheadline.weight(.medium))
            AppKeyListEditor(model: model, apps: $prefs.dataSaver.allowlist, emptyText: "İzin listesi boş.")
        }
    }
}
