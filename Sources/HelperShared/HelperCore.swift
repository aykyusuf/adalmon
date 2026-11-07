import Foundation

/// Yardımcının tüm kararları: komutları uygular, şarj sınırı döngüsünü yürütür, güvenli duruma döner.
/// G/Ç tamamen enjekte edilir (testlerde sahte). Gerçek SMC yazımı yalnızca `Sources/Helper` içindeki cihaz katmanındadır.
actor HelperCore {
    private let smc: SMCAccessing
    private let battery: BatteryProviding
    private let power: PowerSettingApplying
    private let store: HelperStateStoring
    private let scheduler: PollScheduling
    private let clock: @Sendable () -> Date

    private var method: ChargeInhibitMethod?
    private var ledSupported = false
    private var config = ChargeConfig.off
    private var ledMode = MagSafeLEDMode.auto
    private var manualInhibitUntil: Date?
    private var lastError: HelperErrorCode?
    private var lastEvaluation: Date?
    private var lastSnapshot: BatterySnapshot?
    /// SMC okunamazsa son yazdığımız hedef (histerezis sürekliliği).
    private var assumedInhibited = false
    private var polling = false

    init(smc: SMCAccessing, battery: BatteryProviding, power: PowerSettingApplying, store: HelperStateStoring,
         scheduler: PollScheduling, clock: @escaping @Sendable () -> Date = { .now }) {
        self.smc = smc
        self.battery = battery
        self.power = power
        self.store = store
        self.scheduler = scheduler
        self.clock = clock
    }

    // MARK: Yaşam döngüsü

    /// Açılışta: destek tespiti, kayıtlı durumu yükle, EMNİYET: etkin sınır yoksa şarja izin ver.
    func start() {
        var sizes: [SMCKey: Int] = [:]
        for key in SMCKey.allCases { if let d = smc.descriptor(of: key) { sizes[key] = d.size } }
        method = ChargeInhibitMethod.detect(sizes: sizes)
        ledSupported = sizes[.aclc] == 1

        let saved = store.load() ?? HelperPersistedState()
        config = saved.config.isValid ? saved.config : .off
        ledMode = ledSupported ? saved.ledMode : .auto
        if method == nil { config.enabled = false } // destek yoksa sınır asla "açık" kalmaz

        if !config.enabled { ensureChargingAllowed() }
        if ledSupported, ledMode != .auto { _ = smc.write(SMCWriteAllowlist.ledWrite(ledMode)) }
        persist()
        tick()
    }

    /// SIGTERM/SIGINT: donanımı normale döndür (yapılandırma diskte kalır; sonraki açılışta yeniden uygulanır).
    func shutdown() {
        ensureChargingAllowed()
        if ledSupported, ledMode != .auto { _ = smc.write(SMCWriteAllowlist.ledWrite(.auto)) }
        setPolling(false)
    }

    // MARK: Komutlar

    func handle(_ command: HelperCommand) -> HelperReply {
        switch command {
        case .getStatus:
            tickIfNeeded()
            return .success(status())

        case let .setChargeLimit(enabled, limit, floor, topUp):
            if enabled, method == nil { return .failure(.unsupported, status()) }
            var new = ChargeConfig(enabled: enabled, limit: limit, sailingFloor: floor, topUpStartedAt: nil)
            if enabled, topUp { new.topUpStartedAt = config.topUpStartedAt ?? clock() }
            config = new
            if enabled { manualInhibitUntil = nil }
            persist()
            tick()
            return reply()

        case let .setChargingInhibited(inhibited, ttl):
            guard method != nil else { return .failure(.unsupported, status()) }
            if config.enabled { return .failure(.conflictsWithLimit, status()) }
            manualInhibitUntil = inhibited ? clock().addingTimeInterval(TimeInterval(ttl)) : nil
            tick()
            return reply()

        case let .setLowPowerMode(enabled):
            guard power.setLowPowerMode(enabled) else {
                lastError = .pmsetFailure
                return .failure(.pmsetFailure, status())
            }
            if lastError == .pmsetFailure { lastError = nil }
            return .success(status())

        case let .setMagSafeLED(mode):
            guard ledSupported else { return .failure(.unsupported, status()) }
            guard smc.write(SMCWriteAllowlist.ledWrite(mode)) else {
                lastError = .smcFailure
                return .failure(.smcFailure, status())
            }
            ledMode = mode
            persist()
            return .success(status())

        case .resetAll:
            config = .off
            manualInhibitUntil = nil
            ensureChargingAllowed()
            // LED'e yalnızca biz değiştirdiysek dokunulur (doğrulanmamış anahtara gereksiz yazma yok).
            if ledSupported, ledMode != .auto { _ = smc.write(SMCWriteAllowlist.ledWrite(.auto)) }
            ledMode = .auto
            lastError = nil
            persist()
            tick()
            return .success(status())
        }
    }

    /// Doğrulama hatası: durumla birlikte reddet.
    func reject(_ error: HelperErrorCode) -> HelperReply { .failure(error, status()) }

    // MARK: Döngü

    /// IOPS olayı / zamanlayıcı. Yalnızca gerekirken değerlendirir.
    func tickIfNeeded() {
        if manualInhibitUntil != nil || config.enabled { tick() }
    }

    func tick() {
        let now = clock()
        if let until = manualInhibitUntil, until <= now { manualInhibitUntil = nil }
        let snap = battery.snapshot()
        lastSnapshot = snap

        if let method {
            let observed = readInhibiting(method)
            let outcome = ChargeLimitLogic.decide(.init(
                level: snap?.level, isPluggedIn: snap?.isPluggedIn ?? false, isFullyCharged: snap?.isFullyCharged ?? false,
                config: config, manualInhibit: manualInhibitUntil != nil,
                currentlyInhibited: observed ?? assumedInhibited, now: now))
            if outcome.endTopUp {
                config.topUpStartedAt = nil
                persist()
            }
            apply(outcome.decision == .inhibit, method: method, observed: observed)
        }
        lastEvaluation = now
        setPolling(config.enabled || manualInhibitUntil != nil)
    }

    // MARK: Yardımcılar

    private func apply(_ wantInhibit: Bool, method: ChargeInhibitMethod, observed: Bool?) {
        if observed == wantInhibit {
            assumedInhibited = wantInhibit
            if lastError == .smcFailure { lastError = nil }
            return
        }
        guard writeInhibit(wantInhibit, method: method) else {
            failSafeAllow(method)
            return
        }
        // Geri okuma: beklenen durum yoksa güvenli tarafa dön.
        if let after = readInhibiting(method), after != wantInhibit {
            failSafeAllow(method)
            return
        }
        assumedInhibited = wantInhibit
        if lastError == .smcFailure { lastError = nil }
    }

    private func failSafeAllow(_ method: ChargeInhibitMethod) {
        lastError = .smcFailure
        _ = writeInhibit(false, method: method)
        assumedInhibited = false
    }

    private func writeInhibit(_ inhibited: Bool, method: ChargeInhibitMethod) -> Bool {
        var ok = true
        for write in SMCWriteAllowlist.inhibitWrites(method: method, inhibited: inhibited) { ok = smc.write(write) && ok }
        return ok
    }

    private func readInhibiting(_ method: ChargeInhibitMethod) -> Bool? {
        var values: [SMCKey: [UInt8]] = [:]
        for key in method.keys { if let bytes = smc.read(key) { values[key] = bytes } }
        return method.isInhibiting(values)
    }

    /// Şarj engeli varsa (ya da okunamıyorsa) kaldırır. Destek yoksa hiçbir şey yazmaz.
    private func ensureChargingAllowed() {
        guard let method else { return }
        if readInhibiting(method) != false { _ = writeInhibit(false, method: method) }
        assumedInhibited = false
    }

    private func setPolling(_ active: Bool) {
        guard active != polling else { return }
        polling = active
        scheduler.setPolling(active)
    }

    private func persist() { store.save(HelperPersistedState(config: config, ledMode: ledMode)) }

    private func reply() -> HelperReply {
        lastError == .smcFailure ? .failure(.smcFailure, status()) : .success(status())
    }

    func status() -> HelperStatus {
        var s = HelperStatus()
        s.inhibitMethod = method
        s.supportsMagSafeLED = ledSupported
        s.config = config
        s.isInhibitingCharge = method.flatMap { readInhibiting($0) }
        s.manualInhibitUntil = manualInhibitUntil
        s.ledMode = ledMode
        s.batteryLevel = lastSnapshot?.level
        s.isPluggedIn = lastSnapshot?.isPluggedIn
        s.lowPowerMode = power.isLowPowerModeEnabled()
        s.lastError = lastError
        s.lastEvaluation = lastEvaluation
        return s
    }
}
