import SwiftUI
import WidgetKit

/// Halka gösterge (yüzde). Yay `widgetAccentable`: sistem vurgu modunda parlak kalır.
struct WidgetRing<Content: View>: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat = 5
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.012, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            content()
        }
    }
}

/// Yatay doluluk çubuğu.
struct WidgetBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.14))
                Capsule().fill(color)
                    .frame(width: max(height, proxy.size.width * max(0, min(1, fraction))))
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }
}

/// Veri eskimişse en altta görünen not.
struct WidgetStaleNote: View {
    var body: some View {
        Label(WidgetFormat.staleText, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Henüz hiç veri yazılmamış (uygulama hiç çalışmadı).
struct WidgetNoDataView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "bolt.horizontal.circle").font(.system(size: 26)).foregroundStyle(.secondary)
            Text("Adalmon'u aç").font(.system(size: 13, weight: .semibold))
            Text(WidgetFormat.staleText).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }
}

/// Önizleme (uygulama ayarları, testler) için widget çerçevesi. Gerçek widget'ta arka planı sistem verir.
struct WidgetPreviewFrame<Content: View>: View {
    var size: WidgetSize
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: size.canvas.width, height: size.canvas.height)
            .background(.background.secondary, in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.08)))
            .clipShape(.rect(cornerRadius: 22))
    }
}
