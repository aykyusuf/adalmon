import SwiftUI

/// "En çok kullanan uygulamalar" listesi: simge + ad + çubuk + değer. Satıra tıklamak ayrıntı sayfasını açar.
/// Veri gelene kadar gerçek satırla aynı yükseklikte iskelet satırlar gösterilir; sonra çapraz geçişle gerçek satırlara döner.
struct TopProcessList: View {
    let processes: [TopProcess]
    let tint: Color
    var emptyText = "Şu an kayda değer etkinlik yok"
    var isMeasuring = false
    /// İskelette gösterilecek satır sayısı (gerçek listenin tipik uzunluğu).
    var placeholderRows = 5
    var onSelect: ((TopProcess) -> Void)?
    @State private var timedOut = false

    private var state: ListLoadState { .resolve(isLoading: isMeasuring, itemCount: processes.count, timedOut: timedOut) }

    var body: some View {
        SkeletonSwap(isLoading: state == .loading) {
            VStack(alignment: .leading, spacing: 2) {
                if processes.isEmpty {
                    Text(emptyText)
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(processes) { p in
                        Button { onSelect?(p) } label: { TopProcessRow(process: p, tint: tint) }
                            .buttonStyle(.plain)
                            .disabled(onSelect == nil)
                    }
                }
            }
        } placeholder: {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(0..<placeholderRows, id: \.self) { TopProcessRow(process: .placeholder($0), tint: tint, isPlaceholder: true) }
            }
        }
        .loadTimeout($timedOut)
    }
}

/// Tek satır. `isPlaceholder`: aynı yerleşim, içerik soluk bloklar (iskelet).
struct TopProcessRow: View {
    let process: TopProcess
    let tint: Color
    var isPlaceholder = false

    var body: some View {
        HStack(spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(process.name).font(.callout).lineLimit(1)
                    .modifier(SkeletonIf(active: isPlaceholder))
                if isPlaceholder {
                    Capsule().fill(.primary.opacity(0.13)).frame(height: 3)
                } else {
                    UsageBar(fraction: process.fraction, tint: tint, height: 3)
                }
            }
            Text(process.valueText)
                .font(.callout.weight(.medium)).monospacedDigit()
                .frame(minWidth: 52, alignment: .trailing)
                .modifier(SkeletonIf(active: isPlaceholder))
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(process.name), \(process.valueText)")
    }

    @ViewBuilder
    private var icon: some View {
        if isPlaceholder {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.primary.opacity(0.13)).frame(width: 18, height: 18)
        } else {
            Image(nsImage: ResourceDisplay.icon(process.key))
                .resizable().scaledToFit().frame(width: 18, height: 18)
                .accessibilityHidden(true)
        }
    }
}

/// `skeletonBlock` yalnızca etkinken.
struct SkeletonIf: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active { content.skeletonBlock() } else { content }
    }
}

extension TopProcess {
    /// İskelet satırı için sahte içerik (yalnızca yerleşim genişliği için; ekranda blok olarak görünür).
    static func placeholder(_ index: Int) -> TopProcess {
        let names = ["Uygulama adı burada", "Başka bir uygulama", "Sistem süreci", "Uygulama adı", "Kısa ad"]
        return TopProcess(key: "placeholder.\(index)", name: names[index % names.count], valueText: "%00,0", fraction: 0)
    }
}
