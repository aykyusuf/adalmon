import SwiftUI

/// "Yetim dosyalar": uygulaması bulunamayan Library girdileri. Hiçbiri varsayılan seçili değildir.
struct OrphanListView: View {
    @Bindable var model: UninstallerModel

    var body: some View {
        let groups = model.visibleOrphans
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("Uygulamaları artık kurulu olmayan, kimliği tam bir uygulamaya bağlanamayan dosyalar. Liste tahminidir: emin olmadığınız hiçbir şeyi seçmeyin. Varsayılan olarak hiçbiri seçili değil; 1 MB'tan küçük klasörler listelenmez.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if groups.isEmpty {
                    ResourceEmptyNote(text: model.orphans.isEmpty ? "Yetim dosya bulunamadı." : "Aramayla eşleşen yetim yok.")
                }
                ForEach(groups) { group in
                    OrphanGroupCard(group: group, model: model)
                }
            }
            .padding(12)
        }
    }
}

private struct OrphanGroupCard: View {
    let group: OrphanGroup
    @Bindable var model: UninstallerModel

    var body: some View {
        let allSelected = group.items.allSatisfy { model.orphanSelection.contains($0.path) }
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { allSelected }, set: { model.setGroup(group, selected: $0) })) {
                HStack {
                    Text(group.bundleID).font(.headline).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text("\(group.items.count) öğe · \(Format.bytes(group.bytes))").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .toggleStyle(.checkbox)
            ForEach(group.items) { item in
                LeftoverRow(item: item, home: model.home, isOn: Binding(
                    get: { model.orphanSelection.contains(item.path) },
                    set: { if $0 { model.orphanSelection.insert(item.path) } else { model.orphanSelection.remove(item.path) } }
                ))
                .padding(.leading, 20)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
    }
}
