import SwiftUI

/// Ayarlar › Panel: bölüm ve kart sırası/görünürlüğü, yoğunluk, satır sayıları
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
                        PanelReorderRow(title: item.section.displayName, systemImage: item.section.systemImage,
                                        isVisible: sectionVisibility(item.section),
                                        canMoveUp: index > 0, canMoveDown: index < store.config.sections.count - 1) {
                            store.config.move(item.section, by: $0)
                        }
                    }
                }

                Section("Sistem kartları") {
                    ForEach(Array(store.config.cards.enumerated()), id: \.element.id) { index, item in
                        PanelReorderRow(title: item.kind.displayName, systemImage: item.kind.systemImage,
                                        isVisible: cardVisibility(item.kind),
                                        canMoveUp: index > 0, canMoveDown: index < store.config.cards.count - 1) {
                            store.config.move(item.kind, by: $0)
                        }
                    }
                }

                Section {
                    Picker("Zemin", selection: $store.config.background) {
                        ForEach(PanelBackground.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Yoğunluk", selection: $store.config.density) {
                        ForEach(PanelDensity.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Görünüm")
                } footer: {
                    Text("Koyu (opak): koyu yüzey, açık görünümde eşdeğer açık yüzey; parlak duvar kâğıtlarında solmaz. Cam (saydam): Liquid Glass.")
                        .font(.caption).foregroundStyle(.secondary)
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

    private func sectionVisibility(_ section: PanelSection) -> Binding<Bool> {
        let store = model.prefs.panel
        return Binding { store.config.isVisible(section) } set: { store.config.setVisible(section, $0) }
    }

    private func cardVisibility(_ card: PanelCardKind) -> Binding<Bool> {
        let store = model.prefs.panel
        return Binding { store.config.isVisible(card) } set: { store.config.setVisible(card, $0) }
    }

    /// Paneli 0,6 ölçekte çizer. `scaleEffect` yerleşim boyutunu değiştirmediği için çerçeve ölçülen yüksekliğe göre ayarlanır.
    /// Görünüm yalnızca bu bölme açıkken var olur; güncellemeler modelin kendi örnekleme adımıyla gelir (zamanlayıcı yok).
    private var preview: some View {
        let scale = Self.previewScale
        let background = model.prefs.panel.config.background
        return VStack(alignment: .leading, spacing: 8) {
            Text("Önizleme")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                PanelView(model: model, openApp: {}, openSettings: {})
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { previewHeight = $0 }
                    .background { if background == .glass { RoundedRectangle(cornerRadius: 18).fill(.regularMaterial) } }
                    .panelSurface(background)
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
