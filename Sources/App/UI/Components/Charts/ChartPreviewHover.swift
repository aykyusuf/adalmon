import SwiftUI

private struct ChartPreviewHoverKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// Yalnızca önizleme/test: grafiklerde imleç yokken sanki çizim alanının bu oranında (0...1) gelinmiş gibi ipucu gösterir.
    var chartPreviewHover: Double? {
        get { self[ChartPreviewHoverKey.self] }
        set { self[ChartPreviewHoverKey.self] = newValue }
    }
}
