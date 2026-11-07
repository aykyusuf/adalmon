import Foundation

/// Şarj denetimi tercihleri. TÜM özellik bayrakları varsayılan KAPALI; uygulama istenen durumun kaynağıdır.
struct ChargingPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Key {
        static let featureEnabled = "charging.featureEnabled"
        static let ledEnabled = "charging.ledFeatureEnabled"
        static let restoreOnQuit = "charging.restoreOnQuit"
        static let limitEnabled = "charging.limitEnabled"
        static let limit = "charging.limit"
        static let sailingGap = "charging.sailingGap"
        static let led = "charging.led"
    }

    /// Ana şalter: kapalıyken hiçbir yardımcı çağrısı yapılmaz.
    var featureEnabled: Bool {
        get { defaults.bool(forKey: Key.featureEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.featureEnabled) }
    }

    /// MagSafe LED eşlemesi bu Mac'te doğrulanmadığı için ayrı ve varsayılan kapalı.
    var ledFeatureEnabled: Bool {
        get { defaults.bool(forKey: Key.ledEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.ledEnabled) }
    }

    /// Varsayılan AÇIK: uygulama kapanınca normal şarja dönülür.
    var restoreOnQuit: Bool {
        get { defaults.object(forKey: Key.restoreOnQuit) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.restoreOnQuit) }
    }

    var limitEnabled: Bool {
        get { defaults.bool(forKey: Key.limitEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.limitEnabled) }
    }

    var limit: Int {
        get { Self.clampLimit(defaults.object(forKey: Key.limit) as? Int ?? 80) }
        nonmutating set { defaults.set(Self.clampLimit(newValue), forKey: Key.limit) }
    }

    /// Seyir aralığı (limit - alt sınır): 5, 10 ya da 15.
    var sailingGap: Int {
        get { Self.clampGap(defaults.object(forKey: Key.sailingGap) as? Int ?? 5) }
        nonmutating set { defaults.set(Self.clampGap(newValue), forKey: Key.sailingGap) }
    }

    var led: MagSafeLEDMode {
        get { MagSafeLEDMode(rawValue: defaults.integer(forKey: Key.led)) ?? .auto }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.led) }
    }

    static func clampLimit(_ value: Int) -> Int {
        let stepped = Int((Double(value) / Double(HelperConstants.limitStep)).rounded()) * HelperConstants.limitStep
        return min(max(stepped, HelperConstants.limitRange.lowerBound), HelperConstants.limitRange.upperBound)
    }

    static func clampGap(_ value: Int) -> Int { [5, 10, 15].min { abs($0 - value) < abs($1 - value) } ?? 5 }

    /// Seyir alt sınırı: limit - aralık, bekçi tabanının altına inmez.
    static func sailingFloor(limit: Int, gap: Int) -> Int { max(limit - gap, HelperConstants.hardFloorPercent) }
}
