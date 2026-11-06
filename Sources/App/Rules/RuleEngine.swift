import Foundation
import Observation

/// Uygulama başına kullanım kurallarını ve kademeli limiti değerlendirir.
///
/// Pil: değerlendirme yalnızca bellek içi sayaçlarla çalışır (dakika halkaları + sabit pencere sayaçları),
/// SQLite okumaz. Yalnızca kuralı olan uygulamalar için halka tutulur. Zaman `now` olarak dışarıdan verilir.
///
/// Çıktı (`output`) elle ayarlarla birleştirilmemiştir; `EffectiveConfigBuilder` birleştirir.
@MainActor @Observable
final class RuleEngine {
    enum Event: Equatable, Sendable {
        case ruleFired(id: UUID, app: String)
        case ruleLifted(id: UUID, app: String)
        /// Merdiven bu gün ilk kez bu kademeye ulaştı (bildirim için).
        case ladderReached(TierLevel)
    }

    struct Context: Sendable {
        var ownAppKey: String
        var proxyOwnerPaths: [String]
    }

    struct LadderInput: Sendable {
        var dayKey: String
        var dailyUsed: UInt64
        var dailyCap: UInt64
        var cycleUsed: UInt64?
        var monthlyCap: UInt64?
    }

    /// Kayan pencere: tetik eşiğinin bu oranının altına inmeden eylem kalkmaz (histerezis).
    static let releaseRatio = 0.8
    /// Kayan pencere: eylem kalktıktan sonra yeniden tetiklenmeden önce bekleme (sn).
    static let cooldownSeconds: TimeInterval = 60

    // MARK: Gözlemlenen durum (UI)

    private(set) var output = RuleOutput()
    private(set) var ladderStatus = LadderStatus()
    /// Sayaçlar ya da durum değişince artar; UI `statuses` ile birlikte okuyup yenilenir.
    private(set) var revision = 0

    // MARK: İç durum

    @ObservationIgnored private var rules: [UsageRule] = []
    @ObservationIgnored private var rulesByApp: [String: [UsageRule]] = [:]
    @ObservationIgnored private var rollingApps: Set<String> = []
    @ObservationIgnored private var runtimes: [UUID: RuleRuntime] = [:]
    @ObservationIgnored private var rings: [String: MinuteRing] = [:]
    @ObservationIgnored private var pendingEvents: [Event] = []
    /// Merdiven: bugün görülen uygulamalar (toplam ve mobil byte).
    @ObservationIgnored private var seen: [String: (total: UInt64, mobile: UInt64)] = [:]
    @ObservationIgnored private var seenDay: String?
    @ObservationIgnored private var cutSet: [String] = []
    @ObservationIgnored private var persisted = PersistedRuleState()
    @ObservationIgnored private let stateURL: URL?
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var lastSave = Date.distantPast

    /// - Parameter stateURL: Durum dosyası; `nil` ise diske yazılmaz.
    init(stateURL: URL? = RuleStateStore.defaultURL) {
        self.stateURL = stateURL
        if let stateURL {
            persisted = RuleStateStore.load(from: stateURL)
            for (key, rt) in persisted.runtimes {
                if let id = UUID(uuidString: key) { runtimes[id] = rt }
            }
        }
    }

    // MARK: Yapılandırma

    /// Kural listesini güncelle (değişmediyse ucuz çıkış). Silinen / kapatılan kuralların durumu atılır.
    func setRules(_ new: [UsageRule]) {
        guard new != rules else { return }
        rules = new
        let enabled = new.filter(\.enabled)
        rulesByApp = Dictionary(grouping: enabled, by: \.app)
        rollingApps = Set(enabled.filter { !$0.trigger.isFixedWindow }.map(\.app))
        let enabledIDs = Set(enabled.map(\.id))
        let before = runtimes.count
        runtimes = runtimes.filter { enabledIDs.contains($0.key) }
        if runtimes.count != before { dirty = true }
        rings = rings.filter { rollingApps.contains($0.key) }
        revision &+= 1
    }

    /// Yeniden başlatmadan sonra bugünkü uygulama toplamlarını yükle (merdiven aday listesi için).
    func seed(today apps: [AppUsage], dayKey: String) {
        if seenDay != dayKey {
            if seenDay != nil { seen = [:]; cutSet = [] }
            seenDay = dayKey
        }
        for a in apps { seen[a.app] = (a.bytes, a.mobileBytes) }
    }

    // MARK: Besleme

    /// Her ölçüm adımında `UsageEngine.ingest` ile aynı kovalarla çağrılır. Dakika, kovanın kendi dakikasıdır.
    func ingest(_ buckets: [UsageBucket], now: Date) {
        rollWindows(now)
        var touched = false
        for b in buckets where b.kind != .proxyEgress {
            let bytes = b.bytesIn &+ b.bytesOut
            guard bytes > 0 else { continue }
            let mobile: UInt64 = b.expensive ? bytes : 0
            var s = seen[b.app] ?? (0, 0)
            s.total &+= bytes
            s.mobile &+= mobile
            seen[b.app] = s

            guard let appRules = rulesByApp[b.app] else { continue }
            if rollingApps.contains(b.app) {
                rings[b.app, default: MinuteRing(capacity: RuleTrigger.maxRollingMinutes)].add(minute: b.minute, total: bytes, mobile: mobile)
            }
            for rule in appRules where rule.trigger.isFixedWindow {
                let counted = rule.scope == .mobileOnly ? mobile : bytes
                guard counted > 0 else { continue }
                var rt = runtime(for: rule)
                if rt.windowStart == nil { rt.windowStart = now }
                rt.usedBytes &+= counted
                runtimes[rule.id] = rt
                dirty = true
            }
            touched = true
        }
        if touched { revision &+= 1 }
    }

    /// Süresi dolan sabit pencereleri sıfırla ve eylemi kaldır.
    private func rollWindows(_ now: Date) {
        for rule in rules where rule.enabled && rule.trigger.isFixedWindow {
            guard var rt = runtimes[rule.id], let start = rt.windowStart else { continue }
            guard now >= start.addingTimeInterval(TimeInterval(rule.trigger.windowMinutes) * 60) else { continue }
            if rt.activeSince != nil { pendingEvents.append(.ruleLifted(id: rule.id, app: rule.app)) }
            rt.windowStart = nil
            rt.usedBytes = 0
            rt.activeSince = nil
            runtimes[rule.id] = rt
            dirty = true
            revision &+= 1
        }
    }

    private func runtime(for rule: UsageRule) -> RuleRuntime {
        let sig = "\(rule.app)|\(rule.scope.rawValue)|\(rule.trigger.signature)"
        if let rt = runtimes[rule.id], rt.signature == sig { return rt }
        return RuleRuntime(signature: sig)
    }

    // MARK: Değerlendirme

    /// Kuralları ve merdiveni değerlendirir, `output` / `ladderStatus` günceller, yeni olayları döndürür.
    @discardableResult
    func evaluate(now: Date, tier: TierLadderConfig, ladderInput: LadderInput, context: Context) -> [Event] {
        rollWindows(now)
        let nowMinute = Int(now.timeIntervalSince1970 / 60)
        var out = RuleOutput()

        for rule in rules where rule.enabled {
            var rt = runtime(for: rule)
            let before = rt
            let threshold = rule.trigger.thresholdBytes
            switch rule.trigger {
            case .rolling:
                let used = rings[rule.app]?.sum(lastMinutes: rule.trigger.windowMinutes, endingAt: nowMinute, mobileOnly: rule.scope == .mobileOnly) ?? 0
                if let since = rt.activeSince {
                    let release = UInt64(Double(threshold) * Self.releaseRatio)
                    if now.timeIntervalSince(since) >= rule.holdSeconds, used < release {
                        rt.activeSince = nil
                        rt.cooldownUntil = now.addingTimeInterval(Self.cooldownSeconds)
                        pendingEvents.append(.ruleLifted(id: rule.id, app: rule.app))
                    }
                } else if used >= threshold, rule.hasEffect, (rt.cooldownUntil ?? .distantPast) <= now {
                    rt.activeSince = now
                    pendingEvents.append(.ruleFired(id: rule.id, app: rule.app))
                }
            case .fixedWindow:
                if rt.activeSince == nil, rt.windowStart != nil, rt.usedBytes >= threshold, rule.hasEffect {
                    rt.activeSince = now
                    pendingEvents.append(.ruleFired(id: rule.id, app: rule.app))
                }
            }
            if rt != before { runtimes[rule.id] = rt; dirty = true }

            guard rt.activeSince != nil,
                  !ProtectedApps.isEssential(rule.app, ownAppKey: context.ownAppKey, proxyOwnerPaths: context.proxyOwnerPaths) else { continue }
            switch rule.action {
            case .block:
                out.blocked[rule.app, default: []].append(.rule(rule.id))
                if rule.scope == .allNetworks { out.blockedAlways.insert(rule.app) }
            case .throttle:
                if let l = rule.action.limit(scope: rule.scope) {
                    out.limits[rule.app, default: []].append(.init(cause: .rule(rule.id), limit: l))
                }
            }
        }

        let status = evaluateLadder(tier: tier, input: ladderInput, context: context, into: &out)

        if out != output { output = out; revision &+= 1 }
        if status != ladderStatus { ladderStatus = status }
        let events = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        return events
    }

    private func evaluateLadder(tier: TierLadderConfig, input: LadderInput, context: Context, into out: inout RuleOutput) -> LadderStatus {
        // Gün değişti (ilk değerlendirmede ingest'ten gelenleri silme). Aylık limitin tuttuğu kademe gün
        // sınırında bozulmaz: uygulama listesi ve kesme kümesi yalnızca kademe düşmüşse temizlenir.
        let dayChanged = seenDay != nil && seenDay != input.dayKey
        seenDay = input.dayKey
        guard tier.enabled else {
            cutSet = []
            if dayChanged { seen = [:] }
            return LadderStatus()
        }
        let t = tier.normalized
        let pct = TierLadder.percent(dailyUsed: input.dailyUsed, dailyCap: input.dailyCap, cycleUsed: input.cycleUsed, monthlyCap: input.monthlyCap)
        let level = TierLadder.level(percent: pct, config: t)
        var status = LadderStatus(enabled: true, level: level, percent: Int(min(pct, 9999)))
        if dayChanged, level < .slow { seen = [:] }

        if persisted.ladderDay != input.dayKey {
            persisted.ladderDay = input.dayKey
            persisted.ladderMaxLevel = .none
            dirty = true
        }
        if level > persisted.ladderMaxLevel {
            persisted.ladderMaxLevel = level
            dirty = true
            pendingEvents.append(.ladderReached(level))
        }

        func isProtected(_ app: String) -> Bool {
            ProtectedApps.isProtectedFromLadder(app, ownAppKey: context.ownAppKey, proxyOwnerPaths: context.proxyOwnerPaths, userList: t.protectedApps)
        }

        if level >= .slow, let limit = t.slowLimit {
            for app in seen.keys.sorted() where !isProtected(app) {
                out.limits[app, default: []].append(.init(cause: .ladder(.slow), limit: limit))
                status.throttledApps.append(app)
            }
        }
        if level >= .cut {
            // Kesme kümesi yalnızca büyür (gün/kademe değişene kadar); böylece engel kararı titremez.
            let ranked = seen.filter { !isProtected($0.key) && $0.value.mobile > 0 }
                .sorted { $0.value.mobile != $1.value.mobile ? $0.value.mobile > $1.value.mobile : $0.key < $1.key }
                .map(\.key)
            for app in ranked where !cutSet.contains(app) && (t.cutTopCount <= 0 || cutSet.count < t.cutTopCount) {
                cutSet.append(app)
            }
            for app in cutSet {
                out.blocked[app, default: []].append(.ladder(.cut))
                status.blockedApps.append(app)
            }
            if t.appliesTo == .allNetworks {
                out.blockedAlways.formUnion(cutSet)
            }
        } else {
            cutSet = []
        }
        return status
    }

    // MARK: UI durumu

    /// Her kural için anlık durum. `revision` okunur; UI sayaçlar değişince yenilenir.
    func statuses(now: Date, onMobile: Bool) -> [RuleStatus] {
        _ = revision
        let nowMinute = Int(now.timeIntervalSince1970 / 60)
        return rules.map { rule in
            guard rule.enabled else {
                return RuleStatus(id: rule.id, phase: .disabled, usedBytes: 0, thresholdBytes: rule.trigger.thresholdBytes,
                                  isEnforcedNow: false, pendingFilterSupport: false)
            }
            let rt = runtimes[rule.id]
            let active = rt?.activeSince != nil
            var used: UInt64 = 0
            var windowStart: Date?
            var windowEnd: Date?
            var until: TimeInterval?
            if rule.trigger.isFixedWindow {
                used = rt?.usedBytes ?? 0
                windowStart = rt?.windowStart
                windowEnd = windowStart?.addingTimeInterval(TimeInterval(rule.trigger.windowMinutes) * 60)
                until = windowEnd.map { max(0, $0.timeIntervalSince(now)) }
            } else {
                used = rings[rule.app]?.sum(lastMinutes: rule.trigger.windowMinutes, endingAt: nowMinute, mobileOnly: rule.scope == .mobileOnly) ?? 0
                if let since = rt?.activeSince { until = max(0, since.addingTimeInterval(rule.holdSeconds).timeIntervalSince(now)) }
            }
            let phase: RuleStatus.Phase = active ? .active : ((rt?.cooldownUntil ?? .distantPast) > now ? .cooldown : .idle)
            let pending = false // Faz B: Wi-Fi engeli `blockedAlways` ile filtrede uygulanır
            let covers = rule.scope == .allNetworks || onMobile
            let enforced = active && covers
            return RuleStatus(id: rule.id, phase: phase, usedBytes: used, thresholdBytes: rule.trigger.thresholdBytes,
                              windowStart: windowStart, windowEnd: windowEnd, secondsUntilReset: until,
                              isEnforcedNow: enforced, pendingFilterSupport: pending)
        }
    }

    /// Bu uygulamayı şu an sınırlayan / engelleyen kuralların kimlikleri (+ merdiven).
    func causes(for app: String) -> [RuleCause] {
        (output.limits[app]?.map(\.cause) ?? []) + (output.blocked[app] ?? [])
    }

    // MARK: Kalıcılık

    /// Değişiklik varsa (en çok 30 sn'de bir, `force` ile hemen) durumu yazar. `synchronous` testler içindir.
    func persistIfNeeded(now: Date = .now, force: Bool = false, synchronous: Bool = false) {
        guard dirty, let url = stateURL else { return }
        guard force || now.timeIntervalSince(lastSave) >= 30 else { return }
        var state = persisted
        state.runtimes = Dictionary(uniqueKeysWithValues: runtimes.map { ($0.key.uuidString, $0.value) })
        guard let data = RuleStateStore.encode(state) else { return }
        dirty = false
        lastSave = now
        if synchronous {
            RuleStateStore.write(data, to: url)
        } else {
            Task.detached(priority: .utility) { RuleStateStore.write(data, to: url) }
        }
    }
}
