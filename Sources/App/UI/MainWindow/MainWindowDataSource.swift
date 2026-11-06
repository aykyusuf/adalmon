import Foundation

/// Ana pencere sayfalarının okuduğu veri kaynağı. Canlı modda `AppModel`'den, testte sabit örnekten okur.
/// Kapanışlar sayfa `body`'si içinde çağrılır; böylece gözlem yalnızca o sayfanın değerlerine bağlanır.
struct MainWindowDataSource {
    var panelData: @MainActor () -> PanelData
    /// Canlı metrikler (`snapshot`, geçmişler) olmadan; yalnızca ağ/bütçe/engel verisi. Metrik göstermeyen sayfalar bunu okur.
    var pageData: @MainActor () -> PanelData
    var limits: @MainActor () -> [String: AppLimit]

    @MainActor
    static func live(_ model: AppModel) -> MainWindowDataSource {
        MainWindowDataSource(
            panelData: { [unowned model] in PanelData(model: model) },
            pageData: { [unowned model] in PanelData(model: model, live: false) },
            limits: { [unowned model] in model.prefs.appLimits }
        )
    }

    /// Önizleme/test: sabit veri.
    static func fixed(_ data: PanelData, limits: [String: AppLimit] = [:]) -> MainWindowDataSource {
        MainWindowDataSource(panelData: { data }, pageData: { data }, limits: { limits })
    }
}
