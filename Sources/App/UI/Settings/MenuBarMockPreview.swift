import AppKit
import SwiftUI

/// Gerçekçi menü çubuğu maketi: duvar kağıdı, yarı saydam çubuk, sağda sistem simgeleri ve saat;
/// Adalmon öğeleri sistem simgelerinden hemen önce, menü çubuğundaki gibi sağa yaslı durur.
struct MenuBarMockPreview: View {
    let config: MenuBarConfig
    let values: WidgetValues
    let dark: Bool
    var zoom: CGFloat = 2
    /// Sistem simgeleri/saat (galeri kartlarında kapalı).
    var showsSystemItems = true
    /// Çubuğun altında görünen duvar kağıdı payı.
    var wallpaperMargin: CGFloat = 18

    private var barHeight: CGFloat { 24 * zoom }
    private var foreground: Color { dark ? .white : .black }

    var body: some View {
        let items = config.enabledComponents
        let groups = config.displayMode == .combined ? [items] : items.map { [$0] }
        ZStack(alignment: .top) {
            wallpaper
            ZStack(alignment: .trailing) {
                HStack(spacing: 8 * zoom) {
                    if items.isEmpty {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .font(.system(size: 13 * zoom))
                    }
                    ForEach(groups.indices, id: \.self) { i in
                        let image = MenuBarComposer.image(for: groups[i], config: config, values: values,
                                                          appearance: dark ? .darkAqua : .aqua, zoom: zoom)
                        Image(nsImage: image)
                    }
                    if showsSystemItems {
                        systemItems
                    }
                }
                .fixedSize()
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10 * zoom)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
            .frame(height: barHeight)
            .clipped()
            .background(dark ? Color.black.opacity(0.28) : Color.white.opacity(0.42))
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: barHeight + wallpaperMargin * zoom / 2)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dark ? "Koyu" : "Açık") menü çubuğu önizlemesi: \(MenuBarComposer.accessibilitySummary(for: items, values: values))")
    }

    private var systemItems: some View {
        HStack(spacing: 12 * zoom) {
            Image(systemName: "wifi")
            Image(systemName: "switch.2")
            Text(Date.now, format: .dateTime.hour().minute())
        }
        .font(.system(size: 13 * zoom, weight: .medium))
        .padding(.leading, 6 * zoom)
    }

    private var wallpaper: some View {
        LinearGradient(colors: dark
                       ? [Color(red: 0.10, green: 0.12, blue: 0.32), Color(red: 0.36, green: 0.16, blue: 0.46), Color(red: 0.86, green: 0.42, blue: 0.36)]
                       : [Color(red: 0.99, green: 0.86, blue: 0.70), Color(red: 0.86, green: 0.88, blue: 0.99), Color(red: 0.70, green: 0.84, blue: 0.98)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
