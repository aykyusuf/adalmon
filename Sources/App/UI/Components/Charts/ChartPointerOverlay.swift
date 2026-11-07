import Charts
import SwiftUI

/// Grafiğin çizim alanı üzerindeki imleç konumunu x değerine çevirir (tıklama gerekmez; macOS hover).
/// `update` imleç her hareket ettiğinde çağrılır; çağıran yalnızca çözümlenen değer değişince durum yazmalıdır.
struct ChartPointerOverlay<X: Plottable>: View {
    let proxy: ChartProxy
    let update: (X?) -> Void
    @Environment(\.chartPreviewHover) private var previewFraction

    var body: some View {
        GeometryReader { geometry in
            if let anchor = proxy.plotFrame {
                let frame = geometry[anchor]
                Color.clear
                    .contentShape(.rect)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point): update(proxy.value(atX: point.x - frame.minX, as: X.self))
                        case .ended: update(nil)
                        }
                    }
                    .task(id: previewFraction) {
                        if let previewFraction { update(proxy.value(atX: previewFraction * frame.width, as: X.self)) }
                    }
            }
        }
    }
}

extension View {
    /// Grafiğe tıklamadan çalışan imleç takibi ekler; `update(nil)` imleç çıkınca/çizim alanı dışındayken gelir.
    func chartPointer<X: Plottable>(as type: X.Type = X.self, _ update: @escaping (X?) -> Void) -> some View {
        chartOverlay { ChartPointerOverlay<X>(proxy: $0, update: update) }
    }
}
