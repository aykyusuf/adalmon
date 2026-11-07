import SwiftUI

/// Alt eylem kartı: Ayarlar…, Pil ayarları…, Düşük Güç Modu, Adalmon'dan çık.
struct BatteryActionsCard: View {
    let lowPowerControl: BatteryPanelView.LowPowerControl
    let lowPowerOn: Bool
    let actions: PanelActions
    @State private var lowPowerDraft = false

    var body: some View {
        PanelCard(padding: 0) {
            VStack(spacing: 0) {
                row("Ayarlar…", symbol: "gearshape.fill", tint: .secondary, action: actions.openSettings)
                divider
                row("Pil ayarları…", symbol: "battery.100percent", tint: .secondary) { actions.openRoute(.battery) }
                divider
                lowPowerRow
                divider
                row("Adalmon'dan çık", symbol: "power", tint: .red, chevron: false, action: actions.quit)
            }
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
        }
        .onAppear { lowPowerDraft = lowPowerOn }
        .onChange(of: lowPowerOn) { _, new in lowPowerDraft = new }
    }

    private var divider: some View { Divider().opacity(0.45).padding(.leading, 42) }

    @ViewBuilder
    private var lowPowerRow: some View {
        switch lowPowerControl {
        case .toggle:
            HStack(spacing: 10) {
                icon("leaf.fill", .green)
                Text("Düşük Güç Modu").font(.callout)
                Spacer()
                Toggle("Düşük Güç Modu", isOn: $lowPowerDraft).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .onChange(of: lowPowerDraft) { _, new in if new != lowPowerOn { actions.setLowPowerMode(new) } }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
        case .readOnly:
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") { NSWorkspace.shared.open(url) }
            } label: {
                HStack(spacing: 10) {
                    icon("leaf.fill", .green)
                    Text("Düşük Güç Modu").font(.callout)
                    Spacer()
                    Text(lowPowerOn ? "Açık" : "Kapalı").font(.callout).foregroundStyle(lowPowerOn ? Color.yellow : Color.secondary)
                    Image(systemName: "arrow.up.forward").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .contentShape(.rect)
            }
            .buttonStyle(PanelRowButtonStyle())
            .help("Düşük Güç Modu'nu Sistem Ayarları › Pil'den değiştir")
        }
    }

    private func icon(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(tint).frame(width: 20).accessibilityHidden(true)
    }

    private func row(_ title: String, symbol: String, tint: Color, chevron: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon(symbol, tint)
                Text(title).font(.callout)
                Spacer()
                if chevron { Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(PanelRowButtonStyle())
    }
}
