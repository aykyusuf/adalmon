import SwiftUI

/// Başlıktaki "Özelleştir" menüsü: yoğunluk, bölüm görünürlüğü ve Ayarlar.
struct PanelCustomizeMenu: View {
    @Binding var config: PanelConfig
    let openSettings: () -> Void

    var body: some View {
        Menu {
            Picker("Yoğunluk", selection: $config.density) {
                ForEach(PanelDensity.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.inline)
            Picker("Sistem görünümü", selection: $config.tileStyle) {
                ForEach(SystemTileStyle.allCases) { Text($0.displayName).tag($0) }
            }
            Divider()
            Section("Bölümler") {
                ForEach(config.sections) { item in
                    Toggle(item.section.displayName, isOn: visibility(item.section))
                }
            }
            Divider()
            Button("Ayarlar…", systemImage: "gearshape", action: openSettings)
        } label: {
            Label("Özelleştir", systemImage: "gearshape")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Paneli özelleştir")
        .accessibilityLabel("Paneli özelleştir")
    }

    private func visibility(_ section: PanelSection) -> Binding<Bool> {
        Binding {
            config.isVisible(section)
        } set: {
            config.setVisible(section, $0)
        }
    }
}
