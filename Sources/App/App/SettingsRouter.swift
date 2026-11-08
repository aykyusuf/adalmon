import Foundation
import Observation

/// Ayarlar isteklerini yönlendirir: Dock modu açıkken ana pencerede ilgili Ayarlar bölümünü seçer,
/// kapalıyken ayrı Ayarlar penceresini açar. Seçimler iki pencere arasında ortaktır (son kullanılan bölüm).
@MainActor @Observable
final class SettingsRouter {
    /// Ana pencerenin kenar çubuğu seçimi. Bir Ayarlar bölümü seçilince son kullanılan bölüm de güncellenir.
    var selectedMainSection: MainSection = .overview {
        didSet {
            if case .settings(let section) = selectedMainSection { selectedSettingsSection = section }
        }
    }

    /// Son kullanılan Ayarlar bölümü; ayrı Ayarlar penceresinin seçimi de budur.
    var selectedSettingsSection: SettingsSection = .general
    /// Genel bakıştan "Ağ kullanımı"na derin bağlantı: seçilecek uygulama anahtarı (sayfa tüketince nil yapar).
    var selectedAppID: String? = nil
    /// Süreçler sayfasının seçili sekmesi (oturum boyunca korunur; derin bağlantılar da kullanabilir).
    var processesTab: ProcessesTab = .processes

    /// Kayıtlı ana pencere sayfası bu oturumda bir kez geri yüklendi mi (`MainWindowRoot` kullanır).
    @ObservationIgnored var didRestoreMainSection = false

    @ObservationIgnored private let isDockModeOn: @MainActor () -> Bool
    @ObservationIgnored private var showMainWindow: @MainActor () -> Void = {}
    @ObservationIgnored private var showSettingsWindow: @MainActor () -> Void = {}
    @ObservationIgnored private var showOfficeWindow: @MainActor () -> Void = {}

    init(isDockModeOn: @escaping @MainActor () -> Bool) {
        self.isDockModeOn = isDockModeOn
    }

    /// Pencere denetleyicileri oluşturulduktan sonra bağlanır (denetleyiciler yönlendiriciyi, yönlendirici onları kullanır).
    func attach(showMainWindow: @escaping @MainActor () -> Void, showSettingsWindow: @escaping @MainActor () -> Void,
                showOfficeWindow: @escaping @MainActor () -> Void = {}) {
        self.showMainWindow = showMainWindow
        self.showSettingsWindow = showSettingsWindow
        self.showOfficeWindow = showOfficeWindow
        MainWindowCommands.shared.router = self // menü kısayolları (⌘1…⌘5) bu yönlendiriciyi kullanır
    }

    /// Ayrı "Ajan ofisi" penceresini açar (zaten açıksa öne getirir). Dock modundan bağımsızdır.
    func openOfficeWindow() { showOfficeWindow() }

    /// Ayarları açar. `section` verilmezse son kullanılan bölüm (varsayılan: Genel) gösterilir.
    func open(_ section: SettingsSection? = nil) {
        let target = section ?? selectedSettingsSection
        selectedSettingsSection = target
        if isDockModeOn() {
            // Mobil veri ayarları Dock modunda "Mobil veri" sayfasının altındadır (kenar çubuğunda ayrı giriş yok).
            selectedMainSection = MainSection.settings(target).dockCanonical
            showMainWindow()
        } else {
            showSettingsWindow()
        }
    }

    /// Ana pencere şu an bir Ayarlar bölümünü gösteriyor mu?
    /// `adalmon://battery`, widget dokunuşu ve "Adalmon'u aç" kestirmesi. Dock modunda ilgili sayfa, değilse en yakın ayar bölümü.
    func open(route: AdalmonRoute) {
        if isDockModeOn() {
            selectedMainSection = route.mainSection.dockCanonical
            showMainWindow()
        } else {
            open(route.settingsFallback)
        }
    }

    /// Adalmon URL'sini yönlendirir; tanınmazsa `false`.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard let route = AdalmonRoute(url: url) else { return false }
        open(route: route)
        return true
    }

    var mainSectionIsSettings: Bool {
        if case .settings = selectedMainSection { true } else { false }
    }
}
