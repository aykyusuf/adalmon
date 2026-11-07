import SwiftUI

/// "Farklı videolar" kipi: kütüphanedeki uygun videolar küçük resimli karolar; dokununca ekran koruyucuya eklenir/çıkarılır.
struct WallpaperSaverPicker: View {
    @Bindable var wallpaper: WallpaperService
    @Bindable var saver: SaverService

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 10, alignment: .top)]
    private var eligible: [WallpaperItem] { SaverSelection.eligible(wallpaper.items) }

    var body: some View {
        if eligible.isEmpty {
            Text("Kütüphanede video yok. Yukarıdan bir video ekleyin.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(eligible) { item in
                        tile(item)
                    }
                }
                if saver.settings.pickedIDs.isEmpty {
                    Label("Ekran koruyucu için en az bir video seçin.", systemImage: "hand.tap")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private func tile(_ item: WallpaperItem) -> some View {
        let isPicked = saver.settings.pickedIDs.contains(item.id)
        return Button { toggle(item.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Color.clear
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .overlay { WallpaperThumbnail(item: item, service: wallpaper).background(Color.black.opacity(0.2)) }
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isPicked ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isPicked ? 2 : 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isPicked {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .font(.title3)
                                .padding(5)
                        }
                    }
                Text(item.name).font(.caption).lineLimit(1).foregroundStyle(.primary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
        .accessibilityValue(isPicked ? "Seçili" : "Seçili değil")
        .accessibilityAddTraits(.isToggle)
    }

    private func toggle(_ id: UUID) {
        if saver.settings.pickedIDs.contains(id) { saver.settings.pickedIDs.removeAll { $0 == id } }
        else { saver.settings.pickedIDs.append(id) }
    }
}
