import SwiftUI

/// Ortalanmış, kapsül biçimli sekme seçicisi (Süreçler ve Pil sayfaları). Dar alanda yalnızca simgelere düşer.
/// Tek bir odak noktasıdır: odaktayken ←/→ sekme değiştirir. Hareketi azalt açıkken seçili kapsül kaymaz.
struct CapsuleTabBar<Tab: CapsuleTabItem>: View {
    @Binding var selection: Tab
    var accessibilityLabel: LocalizedStringKey = "Görünüm"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace
    @State private var hovered: Tab?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(showsLabels: true)
            bar(showsLabels: false)
        }
        .frame(maxWidth: .infinity)
        .focusable()
        .contentShape(.focusEffect, .capsule)
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isTabBar)
    }

    private func bar(showsLabels: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(Tab.allCases)) { tab in
                CapsuleTabButton(title: tab.title, systemImage: tab.systemImage, isSelected: selection == tab,
                                 showsLabel: showsLabels, isHovered: hovered == tab, namespace: namespace) { select(tab) }
                    .onHover { inside in
                        if inside { hovered = tab } else if hovered == tab { hovered = nil }
                    }
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.6), in: .capsule)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }

    private func select(_ tab: Tab) {
        guard tab != selection else { return }
        if reduceMotion {
            selection = tab
        } else {
            withAnimation(.spring(duration: 0.3, bounce: 0.12)) { selection = tab }
        }
    }

    private func move(_ offset: Int) -> KeyPress.Result {
        let target = selection.neighbor(offset)
        guard target != selection else { return .handled }
        select(target)
        return .handled
    }
}
