import SwiftUI

/// Ayarlar › Panel: bölüm sırası/görünürlüğü, yoğunluk, satır sayıları, sistem görünümü, grafik yüksekliği
/// ve panelin canlı, küçültülmüş önizlemesi.
struct PanelSettingsPane: View {
    let model: AppModel
    @State private var previewHeight: CGFloat = 600

    private static let previewScale: CGFloat = 0.6

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        @Bindable var store = model.prefs.panel
        HStack(alignment: .top, spacing: 0) {
            Form {
                Section("Bölümler") {
                    ForEach(Array(store.config.sections.enumerated()), id: \.element.id) { index, item in
                        sectionRow(item, index: index, count: store.config.sections.count)
                    }
                }

                Section("Görünüm") {
                    Picker("Yoğunluk", selection: $store.config.density) {
                        ForEach(PanelDensity.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Sistem görünümü", selection: $store.config.tileStyle) {
                        ForEach(SystemTileStyle.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Karolarda sıcaklığı göster", isOn: $store.config.showTemperatures)
                    Picker("Ağ grafiği", selection: $store.config.chartHeight) {
                        ForEach(ChartHeight.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Listeler") {
                    Stepper(value: $store.config.last60Rows, in: PanelConfig.rowCountRange) {
                        LabeledContent("Son 60 sn satırı", value: "\(store.config.last60Rows)")
                    }
                    Stepper(value: $store.config.todayRows, in: PanelConfig.rowCountRange) {
                        LabeledContent("Bugün satırı", value: "\(store.config.todayRows)")
                    }
                }

                Section {
                    Button("Varsayılanlara dön") { store.reset() }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 280)

            preview
        }
    }

    private func sectionRow(_ item: PanelSectionItem, index: Int, count: Int) -> some View {
        let store = model.prefs.panel
        return HStack(spacing: 8) {
            Toggle(isOn: Binding {
                store.config.isVisible(item.section)
            } set: {
                store.config.setVisible(item.section, $0)
            }) {
                Label(item.section.displayName, systemImage: item.section.systemImage)
            }
            Spacer()
            Button("Yukarı taşı", systemImage: "chevron.up") { store.config.move(item.section, by: -1) }
                .disabled(index == 0)
            Button("Aşağı taşı", systemImage: "chevron.down") { store.config.move(item.section, by: 1) }
                .disabled(index == count - 1)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
    }

    /// Paneli 0,6 ölçekte çizer. `scaleEffect` yerleşim boyutunu değiştirmediği için çerçeve ölçülen yüksekliğe göre ayarlanır.
    /// Görünüm yalnızca bu bölme açıkken var olur; güncellemeler modelin kendi örnekleme adımıyla gelir (zamanlayıcı yok).
    private var preview: some View {
        let scale = Self.previewScale
        return VStack(alignment: .leading, spacing: 8) {
            Text("Önizleme")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                PanelView(model: model, openSettings: {})
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { previewHeight = $0 }
                    .background(.regularMaterial, in: .rect(cornerRadius: 18))
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: PanelContent.width * scale, height: previewHeight * scale, alignment: .topLeading)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .scrollIndicators(.never)
            Text("Yaklaşık \(Int(previewHeight)) pt yükseklik")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(16)
        .frame(width: PanelContent.width * scale + 32)
    }
}
