import SwiftUI

/// Kütüphane karosu: küçük resim (video üzerinde gezinince önizleme), ad, boyut, "Pil dostu dönüştür".
struct WallpaperTile: View {
    let item: WallpaperItem
    @Bindable var service: WallpaperService
    @State private var hovering = false

    private var isSelected: Bool { service.settings.defaultItemID == item.id }
    private var progress: Double? { service.conversions[item.id]?.progress }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Sabit oranlı kutu: önizleme bunun içine sığdırılır ve kırpılır; aksi halde "fill" resim komşu karoların üstüne taşıyordu.
            Color.clear
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay { preview }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .font(.title3)
                            .padding(6)
                            .accessibilityLabel("Seçili")
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let info = item.info, item.kind == .video {
                        Text(info.qualityText)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: .capsule)
                            .padding(6)
                    }
                }
                .clipShape(.rect(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1) }
                .contentShape(.rect(cornerRadius: 10))
                .onTapGesture { service.settings.defaultItemID = item.id }
                .onHover { hovering = $0 }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(item.name)\(isSelected ? ", seçili" : "")")
                .accessibilityHint("Varsayılan duvar kâğıdı yapmak için çift dokunun")

            Text(item.name).font(.callout.weight(.medium)).lineLimit(1)
            Text(sizeText).font(.caption).foregroundStyle(.secondary).lineLimit(1)

            if !item.fileExists {
                Label("Dosya bulunamadı", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let progress {
                HStack {
                    ProgressView(value: progress)
                    Button("Vazgeç", systemImage: "xmark.circle.fill") { service.cancelConversion(item.id) }
                        .labelStyle(.iconOnly).buttonStyle(.plain)
                }
                Text("Dönüştürülüyor… %\(Int(progress * 100))").font(.caption2).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    if item.kind == .video && !item.isOptimized && item.fileExists {
                        Button("Pil dostu dönüştür", systemImage: "leaf") { service.convert(item.id) }
                            .controlSize(.small)
                            .help("HEVC 1080p, \(service.settings.frameRateCap == .unlimited ? "özgün kare hızı" : "\(service.settings.frameRateCap.rawValue) kare/sn"), ses yok. Kopya Adalmon klasörüne yazılır.")
                    } else if item.isOptimized {
                        Label("Pil dostu", systemImage: "leaf.fill").font(.caption).foregroundStyle(.green)
                    }
                    Spacer(minLength: 0)
                    Button("Kaldır", systemImage: "trash") { service.remove(item.id) }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).controlSize(.small)
                        .help(item.isOptimized ? "Kütüphaneden kaldırır ve dönüştürülmüş kopyayı siler" : "Kütüphaneden kaldırır; dosyanıza dokunulmaz")
                }
            }
        }
    }

    @ViewBuilder private var preview: some View {
        ZStack {
            WallpaperThumbnail(item: item, service: service)
            if hovering, item.kind == .video, item.fileExists {
                WallpaperHoverPreview(url: item.url).transition(.opacity)
            }
        }
        .background(Color.black.opacity(0.2))
        .animation(.easeOut(duration: 0.2), value: hovering)
    }

    private var sizeText: String {
        let size = item.byteSize.formatted(.byteCount(style: .file))
        if let original = item.originalByteSize { return "\(original.formatted(.byteCount(style: .file))) → \(size)" }
        if let info = item.info, item.kind == .image { return "\(info.width) × \(info.height) · \(size)" }
        return size
    }
}
