import SwiftUI

/// Menu bar settings: presets on top, a clickable live menu bar, an inspector for the selected
/// component and a library of ready components that are added with one click.
struct MenuBarSettingsTab: View {
    let model: AppModel
    @Bindable var store: MenuBarConfigStore
    @State private var values = WidgetValues.sample
    @State private var selectedID: MenuBarComponent.ID?

    init(model: AppModel) {
        self.model = model
        self.store = model.prefs.menuBar
    }

    var body: some View {
        Form {
            Section {
                PresetStrip(config: store.config, values: values, current: store.currentPreset) { preset in
                    store.apply(preset)
                    selectedID = store.config.components.first?.id
                }
            } header: {
                HStack {
                    Text("Hazır düzenler")
                    Spacer()
                    Button("Varsayılana dön", systemImage: "arrow.counterclockwise") {
                        store.resetToDefault()
                        selectedID = store.config.components.first?.id
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(store.config == .default)
                }
            }

            Section {
                ViewThatFits(in: .horizontal) {
                    mock(zoom: 2)
                    mock(zoom: 1.5)
                    mock(zoom: 1)
                }
                MenuBarMockPreview(config: store.config, values: values, dark: false, zoom: 1, wallpaperMargin: 8)
            } header: {
                Text("Menü çubuğu")
            } footer: {
                Text("Bir bileşene tıkla ve aşağıda düzenle. Sürükleyerek ya da ←/→ ile sırala, ⌫ ile sil. Alttaki şerit gerçek boyuttur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let index = store.config.components.firstIndex(where: { $0.id == selectedID }) {
                Section("Seçili bileşen") {
                    ComponentInspector(component: $store.config.components[index], config: store.config, values: values,
                                       canMoveLeft: index > 0,
                                       canMoveRight: index < store.config.components.count - 1,
                                       onMove: { store.move(id: store.config.components[index].id, by: $0) },
                                       onDelete: { delete(store.config.components[index].id) })
                        .id(store.config.components[index].id)
                }
            }

            Section {
                ComponentLibraryGrid(config: store.config, values: values) { component in
                    selectedID = store.add(component)
                }
            } header: {
                Text("Bileşen kitaplığı")
            } footer: {
                Text("Kartlar canlı değerlerle çizilir. Tıklayınca bileşen menü çubuğunun sonuna eklenir ve seçilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Düzen") {
                Picker("Gösterim", selection: $store.config.displayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Tıklayınca", selection: $store.config.clickMode) {
                    ForEach(PanelClickMode.allCases) { Text($0.displayName).tag($0) }
                }
                LabeledContent("Aralık") {
                    HStack {
                        Slider(value: $store.config.spacing, in: MenuBarConfig.spacingRange, step: 1)
                        Text("\(Int(store.config.spacing)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent("Etiket opaklığı") {
                    HStack {
                        Slider(value: $store.config.labelOpacity, in: MenuBarConfig.labelOpacityRange, step: 0.05)
                        Text(Format.percent(store.config.labelOpacity))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Birimleri göster", isOn: $store.config.showUnits)
            }
        }
        .formStyle(.grouped)
        .liveWidgetValues($values, model: model)
        .onAppear {
            if selectedID == nil { selectedID = store.config.components.first?.id }
        }
    }

    private func mock(zoom: CGFloat) -> some View {
        MenuBarEditorMock(config: store.config, values: values, selection: $selectedID, zoom: zoom,
                          onMove: { store.move(id: $0, onto: $1) },
                          onMoveBy: { store.move(id: $0, by: $1) },
                          onDelete: delete)
    }

    private func delete(_ id: MenuBarComponent.ID) {
        let index = store.config.components.firstIndex { $0.id == id } ?? 0
        store.remove(id: id)
        let remaining = store.config.components
        selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }
}
