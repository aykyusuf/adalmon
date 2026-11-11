import SwiftUI

/// The form of `MenuBarCardsTab`, separate from live values and the sheet so it can be rendered in tests.
struct MenuBarCardsForm: View {
    @Bindable var store: MenuBarConfigStore
    let values: WidgetValues
    @Binding var cards: [MetricCardConfig]
    let isSimple: Bool
    let onOpenAdvanced: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var pending: LayoutConfirmation?

    var body: some View {
        Form {
            MenuBarUndoSection(store: store)

            Section {
                MenuBarMockPreview(config: store.config, values: values, dark: colorScheme == .dark, zoom: 1.5, wallpaperMargin: 8)
                Picker("Gösterim", selection: $store.config.displayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Tıklayınca", selection: $store.config.clickMode) {
                    ForEach(PanelClickMode.allCases) { Text($0.displayName).tag($0) }
                }
                .help("Menü çubuğu öğesine tıklayınca o metriğin ayrıntı paneli ya da tüm metrikleri tek panelde gösteren birleşik panel açılır.")
                LabeledContent("Aralık") {
                    HStack {
                        Slider(value: $store.config.spacing, in: MenuBarConfig.spacingRange, step: 1)
                        Text("\(Int(store.config.spacing)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                HStack {
                    Text("Önizleme")
                    Spacer()
                    Text("Genişlik: \(Int(totalWidth)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Varsayılana dön", systemImage: "arrow.counterclockwise") {
                        pending = .replacing(store, with: "varsayılan düzen", confirmLabel: "Varsayılana dön") { store.resetToDefault() }
                    }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .disabled(store.config == .default)
                }
            }

            if isSimple {
                Section {
                    ForEach($cards) { $card in
                        let index = cards.firstIndex { $0.id == card.id } ?? 0
                        MetricCardView(card: $card, config: store.config, values: values,
                                       canMoveUp: index > 0, canMoveDown: index < cards.count - 1,
                                       onMove: { move(index, by: $0) })
                    }
                    .onMove { cards.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Metrikler")
                } footer: {
                    Text("Kartların sırası menü çubuğundaki sıradır: sürükleyerek ya da ↑/↓ ile sırala.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Label("Gelişmiş düzende özelleştirildi", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Text("Menü çubuğu, kartlarla gösterilemeyen bileşenlerle ayarlanmış. Basit düzene dönersen varsayılan kartlar uygulanır; gösterim ve aralık korunur.")
                        .foregroundStyle(.secondary)
                    Button("Basit düzene dön", systemImage: "rectangle.grid.1x2") {
                        pending = .replacing(store, with: "varsayılan basit kartlar", confirmLabel: "Basit düzene dön") {
                            store.resetToSimpleLayout()
                        }
                    }
                }
            }

            if !pinnedDevices.isEmpty {
                Section {
                    ForEach(pinnedDevices) { component in
                        HStack {
                            Label(component.deviceName ?? "Cihaz", systemImage: "iphone").labelStyle(.titleAndIcon)
                            Spacer()
                            Button("Menü çubuğundan kaldır", systemImage: "minus.circle") { store.remove(id: component.id) }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                                .help("Menü çubuğundan kaldır")
                        }
                    }
                } header: {
                    Text("Cihaz pilleri")
                } footer: {
                    Text("Cihaz pilleri ayrı menü çubuğu öğeleridir. Yenisini Pil panelindeki cihaz satırından iğne ile ekle.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            MenuBarLayoutsSection(store: store, pending: $pending)

            Section {
                Button("Gelişmiş düzenleyici…", systemImage: "slider.horizontal.3", action: onOpenAdvanced)
            } footer: {
                Text("Hazır düzenler, bileşen kitaplığı, renkler ve grafikler.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .layoutConfirmation($pending)
    }

    private var pinnedDevices: [MenuBarComponent] { store.config.components.filter { $0.deviceID != nil } }

    private var totalWidth: CGFloat {
        let items = store.config.enabledComponents
        guard store.config.displayMode == .separate else {
            return MenuBarComposer.width(of: items, config: store.config, values: values)
        }
        return items.reduce(0) { $0 + MenuBarComposer.width(of: [$1], config: store.config, values: values) }
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard cards.indices.contains(index), cards.indices.contains(target) else { return }
        cards.swapAt(index, target)
    }
}
