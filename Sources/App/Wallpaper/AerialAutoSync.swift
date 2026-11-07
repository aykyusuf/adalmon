import Foundation

/// Sistem listesine (Aerial) kaydettiğimiz videonun kimliği: hangi öğe, hangi boyutta. Bu değişince kayıt yenilenir.
struct AerialRegistration: Codable, Equatable, Sendable {
    var itemID: UUID
    var byteSize: Int64
}

/// "Kilit ekranında da göster" açıkken ne yapılacağını söyleyen SAF mantık (G/Ç yok).
enum AerialAutoSync {
    /// Aerial kaydı için tek video: varsayılan (seçili) video; yoksa kütüphanedeki ilk uygun video.
    static func currentItem(items: [WallpaperItem], defaultID: UUID?) -> WallpaperItem? {
        let usable = items.filter { $0.kind == .video && $0.fileExists }
        return usable.first { $0.id == defaultID } ?? usable.first
    }

    static func registration(for item: WallpaperItem) -> AerialRegistration {
        AerialRegistration(itemID: item.id, byteSize: item.byteSize)
    }

    enum Action: Equatable, Sendable {
        case none
        /// Tek kaydımızı bu videoyla değiştir (Apple'ın kayıtlarına dokunmadan).
        case register(AerialRegistration)
    }

    /// - `registered`: en son başarıyla kaydettiğimiz video. `failed`: bu oturumda hata aldığımız kayıt (döngüye girmemek için).
    static func action(enabled: Bool, canInstall: Bool, status: AerialStatus, current: AerialRegistration?,
                       registered: AerialRegistration?, failed: AerialRegistration?) -> Action {
        guard enabled, canInstall, let current else { return .none }
        if current == failed { return .none }
        if case .installed = status, registered == current { return .none }
        return .register(current)
    }
}
