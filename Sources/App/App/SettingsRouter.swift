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

    @ObservationIgnored private let isDockModeOn: @MainActor () -> Bool
    @ObservationIgnored private var showMainWindow: @MainActor () -> Void = {}
    @ObservationIgnored private var showSettingsWindow: @MainActor () -> Void = {}

    init(isDockModeOn: @escaping @MainActor () -> Bool) {
        self.isDockModeOn = isDockModeOn
    }

    /// Pencere denetleyicileri oluşturulduktan sonra bağlanır (denetleyiciler yönlendiriciyi, yönlendirici onları kullanır).
    func attach(showMainWindow: @escaping @MainActor () -> Void, showSettingsWindow: @escaping @MainActor () -> Void) {
        self.showMainWindow = showMainWindow
        self.showSettingsWindow = showSettingsWindow
    }

    /// Ayarları açar. `section` verilmezse son kullanılan bölüm (varsayılan: Genel) gösterilir.
    func open(_ section: SettingsSection? = nil) {
        let target = section ?? selectedSettingsSection
        selectedSettingsSection = target
        if isDockModeOn() {
            selectedMainSection = .settings(target)
            showMainWindow()
        } else {
            showSettingsWindow()
        }
    }

    /// Ana pencere şu an bir Ayarlar bölümünü gösteriyor mu?
    var mainSectionIsSettings: Bool {
        if case .settings = selectedMainSection { true } else { false }
    }
}
