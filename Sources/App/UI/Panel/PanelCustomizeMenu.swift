import SwiftUI

/// Dişli düğmesi: sol tık uygulamayı/ayarları açar, sağ tık hızlı özelleştirme menüsünü gösterir.
struct PanelCustomizeMenu: View {
    @Binding var config: PanelConfig
    let opensMainWindow: Bool
    let openApp: () -> Void
    let openSettings: () -> Void

    var body: some View {
        let title = opensMainWindow ? "Adalmon'u aç" : "Ayarlar"
        Button(title, systemImage: "gearshape", action: openApp)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(title)
            .contextMenu {
                Picker("Yoğunluk", selection: $config.density) {
                    ForEach(PanelDensity.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Section("Bölümler") {
                    ForEach(config.sections) { item in
                        Toggle(item.section.displayName, isOn: visibility(item.section))
                    }
                }
                Section("Kartlar") {
                    ForEach(config.cards) { item in
                        Toggle(item.kind.displayName, isOn: visibility(item.kind))
                    }
                }
                Divider()
                Button("Ayarlar…", systemImage: "gearshape", action: openSettings)
            }
    }

    private func visibility(_ section: PanelSection) -> Binding<Bool> {
        Binding {
            config.isVisible(section)
        } set: {
            config.setVisible(section, $0)
        }
    }

    private func visibility(_ card: PanelCardKind) -> Binding<Bool> {
        Binding {
            config.isVisible(card)
        } set: {
            config.setVisible(card, $0)
        }
    }
}
