import AppKit
import Foundation
import Observation
import SwiftUI

/// Bir kategorinin tabloda görünen bölümü.
struct ProcessSection: Identifiable {
    var category: ProcessCategory
    /// Üst satırlar; açık gruplarda altlarında üye süreçler (isMember) gelir.
    var rows: [LiveRow]
    var groupCount: Int
    var id: Int { category.rawValue }
}

/// Süreçler sayfasının canlı durumu (İşlemler + Performans sekmeleri). Örnekleme yalnızca sayfa canlı bir sekmedeyken
/// ve ana pencere görünürken çalışır; aralık kullanıcının güncelleme aralığıdır.
///
/// Tablo sırası kararlıdır: sıralama yalnızca sütun/arama/genişletme değişince ya da her `resortEvery`. ölçümde yenilenir;
/// imleç listenin üstündeyken donar (satırlar imlecin altından kaymaz). Sıra yalnızca `apply` ve özellik gözlemcilerinde
/// yazılır, `body`'de değil.
@MainActor @Observable
final class ProcessLiveModel {
    /// Sıralamanın kaç ölçümde bir yenileneceği (kararlılık için).
    static let resortEvery = 3

    private(set) var rows: [LiveRow] = []
    private(set) var members: [String: [LiveRow]] = [:]
    private(set) var totals = ProcessTotals()
    private(set) var latest: SystemSnapshot?
    private(set) var totalProcessCount = 0
    /// Kategorilere ayrılmış, sıralanmış, aramaya uyan görünür satırlar (açık gruplarda üyeler altlarında).
    private(set) var sections: [ProcessSection] = []
    /// İlk örnek yalnız taban çizgisidir; oranlar bir sonraki örnekten sonra gelir.
    private(set) var isMeasuring = true
    /// Örnekleme aralığı (sn).
    private(set) var interval = 2

    var expanded: Set<String> = [] { didSet { if expanded != oldValue { rebuildSections(resort: true) } } }
    var collapsed: Set<ProcessCategory> = [] { didSet { if collapsed != oldValue { rebuildSections(resort: false) } } }
    var query = "" { didSet { if query != oldValue { rebuildSections(resort: true) } } }
    var sortColumn: ProcessColumn = .cpu { didSet { if sortColumn != oldValue { rebuildSections(resort: true) } } }
    var sortAscending = false { didSet { if sortAscending != oldValue { rebuildSections(resort: true) } } }
    var selection: String?

    /// Sonlandırma akışı: önce onay, sonra SIGTERM, hâlâ yaşıyorsa "zorla" onayı.
    var killRequest: KillRequest?
    var forceKillRequest: KillRequest?

    /// "Bilgi" ve "Hız sınırı" sayfaları; alt çubukta kısa süre görünen geri bildirim.
    var infoRow: LiveRow?
    var limitRow: LiveRow?
    private(set) var statusMessage: String?

    struct KillRequest: Identifiable, Equatable {
        var id = UUID()
        var name: String
        var pids: [Int32]
        /// Uygulama paketiyse nazik/zorla kapatma `NSRunningApplication` ile yapılır.
        var appPath: String?
    }

    /// İmleç listenin üstündeyken sıra donar; çıkınca bir sonraki ölçümde yenilenir.
    @ObservationIgnored var isPointerInside = false {
        didSet { if oldValue && !isPointerInside { resortPending = true } }
    }
    @ObservationIgnored private var isSampling = false
    @ObservationIgnored private var pendingMembers = false
    @ObservationIgnored private weak var host: AppModel?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private let cores = ProcessInfo.processInfo.activeProcessorCount
    /// Son sıralamadaki sıra numarası (satır kimliği → sıra); sıralama yenilenmeyen ölçümlerde bu korunur.
    @ObservationIgnored private var orderRank: [String: Int] = [:]
    @ObservationIgnored private var applyCount = 0
    @ObservationIgnored private var resortPending = true

    /// Sistem "Hareketi azalt" ayarı açıksa animasyon yok.
    private var motion: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .smooth(duration: 0.3)
    }

    private var expandMotion: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(duration: 0.28)
    }

    // MARK: Döngü

    func run(service: ResourceService, model: AppModel) async {
        host = model
        await service.live.reset()
        isMeasuring = true
        var first = true
        while !Task.isCancelled {
            let visible = model.mainWindowVisible
            if visible { await refresh(service: service, model: model) }
            // Pencere küçültülmüş / örtülüyken boşuna uyanma (pil): seyrek yokla.
            let seconds = !visible ? 5 : first ? 1 : max(1, model.prefs.updateInterval)
            if visible { interval = seconds }
            first = false
            try? await Task.sleep(for: .seconds(seconds), tolerance: .milliseconds(seconds * 150))
        }
    }

    /// Tek uçuşlu: üst üste biniyorsa atlanır. `membersOnly`: yalnızca yeni açılan grupların üyelerini al (satır oranları
    /// kısa pencereyle bozulmasın); uçuştaki ölçüm bitince hemen yeniden çalışır (açma bir aralık beklemesin).
    func refresh(service: ResourceService, model: AppModel, membersOnly: Bool = false) async {
        guard !isSampling else {
            if membersOnly { pendingMembers = true }
            return
        }
        isSampling = true
        defer { isSampling = false }
        let snap = await service.live.sample(expanded: expanded)
        if membersOnly {
            applyMembers(snap)
        } else {
            apply(snap, snapshot: model.snapshot, net: model.usage.last60Bytes)
        }
        if pendingMembers {
            pendingMembers = false
            applyMembers(await service.live.sample(expanded: expanded))
        }
    }

    func setExpanded(_ key: String, _ value: Bool, service: ResourceService, model: AppModel) {
        withAnimation(expandMotion) {
            if value { expanded.insert(key) } else { expanded.remove(key); members[key] = nil }
        }
        if value { Task { await refresh(service: service, model: model, membersOnly: true) } }
    }

    func apply(_ snap: LiveSnapshot, snapshot: SystemSnapshot?, net: [String: UInt64]) {
        isMeasuring = snap.elapsed == 0
        totalProcessCount = snap.totalProcessCount
        let regular = Set(NSWorkspace.shared.runningApplications.lazy.filter { $0.activationPolicy == .regular }.compactMap { $0.bundleURL?.path })
        var out: [LiveRow] = []
        var mem: [String: [LiveRow]] = [:]
        out.reserveCapacity(snap.groups.count)
        for g in snap.groups {
            // Önce ucuz oranlar ve boşta filtresi: ad/kategori (önbelleksiz yol çözümleme) yalnızca görünecek ~40 grup için.
            let rates = LiveRow.Rates(usage: g.usage, elapsed: snap.elapsed, cores: cores)
            let networkBytes = Double(net[g.key] ?? 0)
            if g.usage.footprint < 1_000_000, rates.cpu < 0.05, rates.disk < 1, rates.gpu < 0.05, networkBytes < 60 { continue }
            var row = LiveRow.make(group: g, elapsed: snap.elapsed, cores: cores, name: ResourceDisplay.name(g.key),
                                   category: ProcessCategory.classify(key: g.key, regularAppPaths: regular),
                                   networkBytes: networkBytes)
            if row.category != .system {
                let state = ProcessActions.state(of: g.pids)
                row.isSuspended = state.isSuspended
                row.isEfficient = state.isEfficient
            }
            out.append(row)
            if !g.members.isEmpty { mem[g.key] = memberRows(g.members, group: row, snap: snap) }
        }
        let hints = DuplicateNameHints.hints(keys: out.map(\.key), name: { ResourceDisplay.name($0) })
        if !hints.isEmpty {
            for i in out.indices { out[i].pathHint = hints[out[i].key] }
        }
        rows = out
        members = mem
        totals = ProcessTotals(snapshot: snapshot, rows: out)
        if let snapshot { latest = snapshot }
        applyCount += 1
        // Sıra yalnızca seyrek yenilenir ve imleç listedeyken donar; yalnızca gerçek yeniden sıralama animasyonlu.
        let reorder = resortPending || (applyCount % Self.resortEvery == 0 && !isPointerInside)
        if reorder {
            withAnimation(motion) { rebuildSections(resort: true) }
        } else {
            rebuildSections(resort: false)
        }
    }

    /// Yeni açılan grupların üyelerini ekler (zaten gösterilenlerin oranlarına dokunmaz); animasyonlu.
    private func applyMembers(_ snap: LiveSnapshot) {
        var changed = false
        var next = members
        for g in snap.groups where expanded.contains(g.key) && next[g.key] == nil && !g.members.isEmpty {
            guard let row = rows.first(where: { $0.key == g.key }) else { continue }
            next[g.key] = memberRows(g.members, group: row, snap: snap)
            changed = true
        }
        guard changed else { return }
        withAnimation(expandMotion) {
            members = next
            rebuildSections(resort: false)
        }
    }

    private func memberRows(_ list: [LiveMember], group: LiveRow, snap: LiveSnapshot) -> [LiveRow] {
        list.map { member in
            var m = LiveRow.make(member: member, group: group, elapsed: snap.elapsed, cores: cores)
            if m.category != .system {
                let state = ProcessActions.state(of: member.pids)
                m.isSuspended = state.isSuspended
                m.isEfficient = state.isEfficient
            }
            return m
        }
    }

    // MARK: Görünüm verisi

    /// Aramaya uyan, sıralanmış, kategoriye ayrılmış bölümleri kurar. `resort` false ise önceki sıra korunur
    /// (yeni satırlar sıralı konumlarına eklenir, kaybolanlar düşer).
    private func rebuildSections(resort: Bool) {
        let doResort = resort || resortPending
        resortPending = false
        let needle = query.trimmingCharacters(in: .whitespaces)
        let filtered = needle.isEmpty ? rows : rows.filter { $0.name.localizedStandardContains(needle) }
        if doResort { orderRank = [:] }
        let ordered = stableOrder(filtered, resort: doResort)
        sections = ProcessCategory.allCases.compactMap { category in
            let groups = ordered.filter { $0.category == category }
            guard !groups.isEmpty else { return nil }
            var flat: [LiveRow] = []
            if !collapsed.contains(category) {
                for g in groups {
                    flat.append(g)
                    if expanded.contains(g.key) {
                        flat.append(contentsOf: stableOrder(members[g.key] ?? [], resort: doResort))
                    }
                }
            }
            return ProcessSection(category: category, rows: flat, groupCount: groups.count)
        }
    }

    private func stableOrder(_ list: [LiveRow], resort: Bool) -> [LiveRow] {
        let fresh = sorted(list)
        var result: [LiveRow]
        if resort {
            result = fresh
        } else {
            let rank = orderRank
            let known = list.filter { rank[$0.id] != nil }.sorted { rank[$0.id, default: 0] < rank[$1.id, default: 0] }
            let unknown = Set(list.lazy.filter { rank[$0.id] == nil }.map(\.id))
            result = known
            if !unknown.isEmpty {
                // Yeni satır, sıralı listede kendinden önce gelen bilinen satır sayısı kadar yere girer.
                let knownIDs = Set(known.map(\.id))
                var seenKnown = 0
                for row in fresh {
                    if unknown.contains(row.id) { result.insert(row, at: min(seenKnown, result.count)) }
                    else if knownIDs.contains(row.id) { seenKnown += 1 }
                }
            }
        }
        for (i, r) in result.enumerated() { orderRank[r.id] = i }
        return result
    }

    func canExpand(_ row: LiveRow) -> Bool { !row.isMember && row.processCount > 1 }

    func row(id: String?) -> LiveRow? {
        guard let id else { return nil }
        if let r = rows.first(where: { $0.id == id }) { return r }
        for list in members.values { if let r = list.first(where: { $0.id == id }) { return r } }
        return nil
    }

    func sort(by column: ProcessColumn) {
        if sortColumn == column { sortAscending.toggle() } else { sortColumn = column; sortAscending = column.defaultAscending }
    }

    private func sorted(_ list: [LiveRow]) -> [LiveRow] {
        list.sorted { a, b in
            if sortColumn == .name {
                let c = a.name.localizedStandardCompare(b.name)
                return sortAscending ? c == .orderedAscending : c == .orderedDescending
            }
            let x = sortColumn.value(of: a), y = sortColumn.value(of: b)
            if x != y { return sortAscending ? x < y : x > y }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    // MARK: Eylemler

    func requestKill(_ row: LiveRow) {
        guard canKill(row) else { return }
        let appPath = row.category == .app && !row.isMember && row.key.hasSuffix(".app") ? row.key : nil
        killRequest = KillRequest(name: row.name, pids: ProcessActions.killablePIDs(row.pids), appPath: appPath)
    }

    /// Sistem (macOS) kategorisi hiç değiştirilemez: `loginwindow` ve launchd kovası (`__system__`) kullanıcının kendi
    /// uid'sinde çalışır; tek onayla oturumu kapatabilir ya da yüzlerce sistem sürecini keserdi.
    func canKill(_ row: LiveRow) -> Bool { permissions(for: row).canControl }

    func permissions(for row: LiveRow) -> ProcessPermissions {
        ProcessPermissions.evaluate(category: row.category, key: row.key, isMember: row.isMember,
                                    ownedCount: row.category == .system ? 0 : ProcessActions.killablePIDs(row.pids).count,
                                    totalCount: row.pids.count)
    }

    /// Onaydan sonra: nazikçe kapat (uygulamaysa `terminate`, değilse SIGTERM); 3 sn sonra hâlâ yaşayan varsa "zorla" sorusu.
    func confirmKill(_ request: KillRequest) {
        killRequest = nil
        // Onay penceresi uzun açık kalmış olabilir (pid yeniden kullanımı): sinyalden hemen önce yeniden süz.
        let pids = ProcessActions.alive(ProcessActions.killablePIDs(request.pids))
        let handledAsApp = request.appPath.map { ProcessActions.terminateApplication(bundlePath: $0, force: false) } ?? false
        if !handledAsApp { ProcessActions.terminate(pids) }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            let remaining = ProcessActions.alive(pids)
            if !remaining.isEmpty { self?.forceKillRequest = KillRequest(name: request.name, pids: remaining, appPath: request.appPath) }
            self?.refreshSoon()
        }
    }

    func confirmForceKill(_ request: KillRequest) {
        forceKillRequest = nil
        if let path = request.appPath { _ = ProcessActions.terminateApplication(bundlePath: path, force: true) }
        ProcessActions.forceKill(ProcessActions.alive(ProcessActions.killablePIDs(request.pids)))
        refreshSoon()
    }

    // MARK: Askıya alma / öncelik / verimlilik / diğer

    func toggleSuspend(_ row: LiveRow) {
        let pids = ProcessActions.killablePIDs(row.pids)
        guard permissions(for: row).canControl, !pids.isEmpty else { return }
        if row.isSuspended {
            ProcessActions.resume(pids)
            setStatus("“\(row.name)” devam ettirildi")
        } else {
            ProcessActions.suspend(pids)
            setStatus("“\(row.name)” askıya alındı (SIGSTOP)")
        }
        refreshSoon()
    }

    func setNice(_ row: LiveRow, to target: Int32) {
        let pids = ProcessActions.killablePIDs(row.pids)
        guard permissions(for: row).canControl, !pids.isEmpty else { return }
        var changed = 0
        for pid in pids {
            switch ProcessPriorityPlan.evaluate(currentNice: ProcessActions.nice(of: pid) ?? 0, target: target) {
            case .apply(let value): changed += ProcessActions.setNice([pid], to: value)
            case .noChange, .needsRoot: break
            }
        }
        setStatus(changed > 0 ? "“\(row.name)” önceliği düşürüldü (nice \(target))" : "Öncelik değişmedi (artırmak root gerektirir)")
        refreshSoon()
    }

    /// Verimlilik modu açıkken satırın nice değeri geri alınamaz ama bu mod her zaman geri alınabilir.
    func toggleEfficiency(_ row: LiveRow) {
        let pids = ProcessActions.killablePIDs(row.pids)
        guard permissions(for: row).canControl, !pids.isEmpty else { return }
        ProcessActions.setEfficiency(pids, on: !row.isEfficient)
        setStatus(row.isEfficient ? "“\(row.name)” verimlilik modundan çıktı" : "“\(row.name)” verimlilik modunda")
        refreshSoon()
    }

    func restart(_ row: LiveRow) {
        guard permissions(for: row).canRestart, let host else { return }
        host.restartApp(row.key)
        setStatus("“\(row.name)” yeniden başlatılıyor…")
    }

    func sample(_ row: LiveRow) {
        guard let pid = row.pid ?? row.pids.min() else { return }
        setStatus("“\(row.name)” için 3 sn'lik örnek alınıyor…", clearAfter: 30)
        let name = row.name
        Task { [weak self] in
            let url = await Task.detached(priority: .utility) { ProcessActions.sampleProcess(pid: pid, name: name) }.value
            if let url {
                self?.setStatus("Örnek kaydedildi: \(url.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                self?.setStatus("Örnek alınamadı (süreç kapanmış ya da izin yok)")
            }
        }
    }

    func toggleBlockOnMobile(_ row: LiveRow) {
        guard let host, permissions(for: row).canNetworkControl else { return }
        let blocked = host.prefs.blockedOnMobile.contains(row.key)
        host.setBlocked(row.key, !blocked)
        setStatus(blocked ? "“\(row.name)” mobil engeli kaldırıldı" : "“\(row.name)” mobilde engellendi")
    }

    func resetConnections(_ row: LiveRow) {
        guard let host, permissions(for: row).canNetworkControl else { return }
        host.resetConnections(for: row.key)
        setStatus("“\(row.name)” bağlantıları yenileniyor…")
    }

    func setStatus(_ message: String, clearAfter seconds: Double = 6) {
        statusMessage = message
        statusTask?.cancel()
        statusTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }

    private func refreshSoon() {
        guard let host else { return }
        Task { await refresh(service: host.resources, model: host) }
    }

    /// "Bilgi kopyala" metni.
    func infoText(for row: LiveRow) -> String {
        var lines = [row.name]
        if let path = row.path { lines.append("Yol: \(path)") }
        lines.append(row.isMember ? "PID: \(row.pids.map(String.init).joined())" : "Süreçler (\(row.processCount)): \(row.pids.prefix(40).map(String.init).joined(separator: ", "))")
        lines.append("CPU: \(ResourceFormat.percent(row.cpu))  Bellek: \(ResourceFormat.bytes(row.memory))  GPU: \(ResourceFormat.percent(row.gpu))")
        lines.append("Disk: \(Format.rate(row.disk))  Ağ (60 sn ort.): \(Format.rate(row.network))  Enerji: \(ResourceFormat.watts(row.energy))")
        return lines.joined(separator: "\n")
    }
}
