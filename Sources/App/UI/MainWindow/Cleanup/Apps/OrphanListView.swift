import SwiftUI

/// "Yetim dosyalar": uygulaması bulunamayan Library girdileri, kimliğe göre grup kartları. Hiçbiri varsayılan seçili değildir.
/// Kaydırma üstteki sayfa tarafından yapılır.
struct OrphanListView: View {
    @Bindable var model: UninstallerModel
    @State private var expanded: Set<String> = []

    private let accent = CleanupAccent.uninstaller

    var body: some View {
        let groups = model.visibleOrphans
        LazyVStack(spacing: 8) {
            if groups.isEmpty {
                CleanupAllCleanView(
                    accent: accent, title: model.orphans.isEmpty ? "Yetim dosya yok" : "Eşleşen yetim yok",
                    subtitle: model.orphans.isEmpty ? "Uygulaması kalmayan dosya bulunamadı." : "Aramayla eşleşen yetim dosya yok.", compact: true
                )
            }
            ForEach(groups) { group in
                let selectedCount = group.items.filter { model.orphanSelection.contains($0.path) }.count
                CleanupResultCard(
                    symbol: "shippingbox", title: group.bundleID,
                    subtitle: "\(group.items.count) öğe · uygulaması kurulu değil", sizeText: Format.bytes(group.bytes), accent: accent,
                    selection: CleanupSelectionState(selected: selectedCount, total: group.items.count),
                    isEnabled: !model.isBusy,
                    onToggle: { model.setGroup(group, selected: selectedCount < group.items.count) },
                    isExpanded: Binding(get: { expanded.contains(group.id) },
                                        set: { if $0 { expanded.insert(group.id) } else { expanded.remove(group.id) } })
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(group.items) { item in
                            LeftoverRow(item: item, home: model.home, isOn: Binding(
                                get: { model.orphanSelection.contains(item.path) },
                                set: { if $0 { model.orphanSelection.insert(item.path) } else { model.orphanSelection.remove(item.path) } }
                            ))
                        }
                    }
                }
            }
        }
    }
}
