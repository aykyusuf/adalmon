import Darwin
import Foundation

/// Sekme ↔ süreç eşlemesi (ölçerek). Safari de Chrome de "hangi süreç hangi sekme" bilgisini vermez. Çözüm: sekmede kısa (≈150 ms)
/// bir JavaScript döngüsü çalıştırıp hangi sürecin CPU süresinin arttığına bakmak. Sekme başına bir kez, kullanıcı isteğiyle çalışır;
/// iki sekme aynı süreci paylaşıyorsa ikisi de o sürece eşlenir (RAM ortaktır).
enum TabProcessProbe {
    static let spinMilliseconds = 150
    /// Sekmede çalıştırılan döngü (sayfanın içeriğine hiçbir şey yazmaz/okumaz).
    static let spinSource = "(function(){var t=Date.now();while(Date.now()-t<\(spinMilliseconds)){}return 1})()"

    /// `before`/`after`: süreç → kümülatif CPU saniyesi. En çok artan süreç, artış en az döngünün yarısı kadarsa VE ikinci
    /// en yüksek artışın en az iki katıysa o sürecin pid'i; belirsizse (başka bir süreç de yoğun çalışıyorsa) nil.
    static func attribute(before: [Int32: Double], after: [Int32: Double], spinSeconds: Double = Double(spinMilliseconds) / 1000) -> Int32? {
        var deltas: [(pid: Int32, delta: Double)] = []
        for (pid, a) in after {
            guard let b = before[pid], a >= b else { continue }
            deltas.append((pid, a - b))
        }
        deltas.sort { $0.delta != $1.delta ? $0.delta > $1.delta : $0.pid < $1.pid }
        guard let top = deltas.first, top.delta >= spinSeconds * 0.5 else { return nil }
        if deltas.count > 1, deltas[1].delta > top.delta * 0.5 { return nil }
        return top.pid
    }
}

/// Bir sürecin kümülatif CPU süresi (saniye); aynı kullanıcının süreçleri dışında nil.
enum ProcessCPU {
    static func seconds(of pid: Int32) -> Double? {
        guard let found = CoalitionAPI.processCounters(of: pid) else { return nil }
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        guard info.denom > 0 else { return nil }
        return Double(found.counters.cpuTicks) * Double(info.numer) / Double(info.denom) / 1e9
    }
}

/// Eşleme sonucu özeti: hangi sekmeler hangi sürece düştü.
struct TabProcessMap: Equatable, Sendable {
    /// sekme anahtarı → süreç kimliği
    var pidByTab: [String: Int32] = [:]
    var updatedAt: Date?

    var isEmpty: Bool { pidByTab.isEmpty }

    /// Bir süreci paylaşan sekme sayısı.
    func sharedCount(for pid: Int32) -> Int { pidByTab.values.filter { $0 == pid }.count }

    func tabKeys(for pid: Int32) -> [String] { pidByTab.filter { $0.value == pid }.map(\.key).sorted() }
}

/// Eşleme durumu (arayüz).
enum TabProbeState: Equatable, Sendable {
    case idle
    case running(done: Int, total: Int)
    case finished(mapped: Int, total: Int)
    /// Safari: "Apple Events'ten JavaScript'e izin ver" (Develop menüsü) kapalı.
    case javascriptDisabled
    case failed(String)
}

/// Süreçler listesinin tarayıcı alt süreçlerinin yanına sekme başlığı yazabilmesi için son eşlemenin süreç → başlıklar özeti.
@MainActor
final class BrowserTabMapStore {
    static let shared = BrowserTabMapStore()
    private(set) var titlesByPID: [Int32: [String]] = [:]
    private var bySource: [String: [Int32: [String]]] = [:]

    func set(source: String, titles: [Int32: [String]]) {
        bySource[source] = titles
        var merged: [Int32: [String]] = [:]
        for (_, map) in bySource { merged.merge(map) { a, b in a + b } }
        if merged != titlesByPID { titlesByPID = merged }
    }

    func clear(source: String) { set(source: source, titles: [:]) }

    /// "YouTube · X" ya da "YouTube +2" (en çok iki başlık gösterilir).
    func label(for pid: Int32) -> String? {
        guard let titles = titlesByPID[pid], !titles.isEmpty else { return nil }
        let shown = titles.prefix(2).map { $0.count > 28 ? String($0.prefix(27)) + "…" : $0 }
        let extra = titles.count - shown.count
        return shown.joined(separator: " · ") + (extra > 0 ? " +\(extra)" : "")
    }
}
