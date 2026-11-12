import Foundation

/// Canlı listenin son 1 saatlik dakika kovalarının kalıcı hâli (yeniden başlatmada korunur).
/// Yalnızca kullanım verisi: sınır/engel durumu burada tutulmaz. Saniye halkası (son 60 sn) kaydedilmez.
struct LiveUsageSnapshot: Equatable, Sendable {
    /// Kaydedildiği an (Unix saniyesi); tanı amaçlı. Geçerlilik dakika kovalarının kendisinden hesaplanır.
    var savedAt: Int = 0
    /// Unix dakikası → uygulama anahtarı → trafik.
    var minutes: [Int: [String: LiveTraffic]] = [:]

    var isEmpty: Bool { minutes.isEmpty }

    // MARK: İkili biçim
    //
    // "ALUS" | sürüm(1) | varint savedAt | varint uygulama sayısı, {varint uzunluk, UTF-8} |
    // varint dakika sayısı, { varint dakika, varint kayıt sayısı, { varint uygulama#, down, up, mobileDown, mobileUp } } |
    // FNV-1a 32 bit (little endian, önceki tüm baytlar üzerinde).
    // Sayılar LEB128 (küçük değerler 1 bayt) olduğundan tipik dosya birkaç on KB'yi geçmez.

    private static let magic: [UInt8] = Array("ALUS".utf8)
    private static let version: UInt8 = 1
    /// Bozuk dosyada devasa bellek ayrılmasın diye üst sınırlar.
    private static let maxApps = 2_000
    private static let maxMinutes = 200
    private static let maxNameBytes = 4_096

    func encoded() -> Data {
        var names = Set<String>()
        for apps in minutes.values { names.formUnion(apps.keys) }
        let table = names.sorted()
        let index = Dictionary(uniqueKeysWithValues: table.enumerated().map { ($1, $0) })

        var out = Self.magic
        out.append(Self.version)
        Self.putVarint(UInt64(max(0, savedAt)), to: &out)
        Self.putVarint(UInt64(table.count), to: &out)
        for name in table {
            let bytes = Array(name.utf8)
            Self.putVarint(UInt64(bytes.count), to: &out)
            out.append(contentsOf: bytes)
        }
        let keys = minutes.keys.filter { $0 >= 0 }.sorted()
        Self.putVarint(UInt64(keys.count), to: &out)
        for minute in keys {
            let entries = minutes[minute, default: [:]].filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }
            Self.putVarint(UInt64(minute), to: &out)
            Self.putVarint(UInt64(entries.count), to: &out)
            for (app, t) in entries {
                Self.putVarint(UInt64(index[app] ?? 0), to: &out)
                Self.putVarint(t.down, to: &out)
                Self.putVarint(t.up, to: &out)
                Self.putVarint(t.mobileDown, to: &out)
                Self.putVarint(t.mobileUp, to: &out)
            }
        }
        var sum = Self.checksum(out)
        for _ in 0..<4 { out.append(UInt8(truncatingIfNeeded: sum)); sum >>= 8 }
        return Data(out)
    }

    /// Bozuk / kesik / yabancı veri için `nil` (asla çökmez).
    static func decode(_ data: Data) -> LiveUsageSnapshot? {
        let bytes = [UInt8](data)
        guard bytes.count >= magic.count + 1 + 4, bytes.starts(with: magic), bytes[magic.count] == version else { return nil }
        let body = Array(bytes.dropLast(4))
        var stored: UInt32 = 0
        for (i, b) in bytes.suffix(4).enumerated() { stored |= UInt32(b) << (8 * UInt32(i)) }
        guard stored == checksum(body) else { return nil }

        var r = Reader(bytes: body, pos: magic.count + 1)
        guard let savedAt = r.varint(), savedAt <= UInt64(Int.max),
              let appCount = r.varint(), appCount <= UInt64(maxApps) else { return nil }
        var table: [String] = []
        table.reserveCapacity(Int(appCount))
        for _ in 0..<appCount {
            guard let len = r.varint(), len <= UInt64(maxNameBytes), let raw = r.take(Int(len)),
                  let name = String(data: Data(raw), encoding: .utf8) else { return nil }
            table.append(name)
        }
        guard let minuteCount = r.varint(), minuteCount <= UInt64(maxMinutes) else { return nil }
        var result = LiveUsageSnapshot(savedAt: Int(savedAt))
        for _ in 0..<minuteCount {
            guard let minute = r.varint(), minute <= UInt64(Int32.max),
                  let n = r.varint(), n <= appCount else { return nil }
            var apps: [String: LiveTraffic] = [:]
            for _ in 0..<n {
                guard let i = r.varint(), i < UInt64(table.count),
                      let down = r.varint(), let up = r.varint(),
                      let mDown = r.varint(), let mUp = r.varint() else { return nil }
                apps[table[Int(i)], default: LiveTraffic()].add(LiveTraffic(down: down, up: up, mobileDown: mDown, mobileUp: mUp))
            }
            if !apps.isEmpty { result.minutes[Int(minute), default: [:]].merge(apps) { a, b in var s = a; s.add(b); return s } }
        }
        guard r.atEnd else { return nil }
        return result
    }

    // MARK: Düşük seviye

    private static func putVarint(_ value: UInt64, to out: inout [UInt8]) {
        var v = value
        while v >= 0x80 { out.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }
        out.append(UInt8(v))
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var h: UInt32 = 0x811C_9DC5
        for b in bytes { h = (h ^ UInt32(b)) &* 0x0100_0193 }
        return h
    }

    private struct Reader {
        let bytes: [UInt8]
        var pos: Int
        var atEnd: Bool { pos == bytes.count }

        mutating func varint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while pos < bytes.count, shift < 64 {
                let b = bytes[pos]
                pos += 1
                if shift == 63, b > 1 { return nil }
                result |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return result }
                shift += 7
            }
            return nil
        }

        mutating func take(_ n: Int) -> ArraySlice<UInt8>? {
            guard n >= 0, bytes.count - pos >= n else { return nil }
            defer { pos += n }
            return bytes[pos..<(pos + n)]
        }
    }
}

extension LiveUsageHistory {
    /// Diske yazılan en çok uygulama sayısı (en çok trafik yapanlar kalır).
    static let maxPersistedApps = 200

    /// Son 1 saatin dakika kovaları; kaydedilmeyecek kadar eski ya da gelecekteki (saat geri gitmiş) kovalar dışarıda.
    func snapshot(nowMinute: Int, savedAt: Int, maxApps: Int = LiveUsageHistory.maxPersistedApps) -> LiveUsageSnapshot {
        var kept = minutesInWindow(nowMinute: nowMinute)
        var totals: [String: UInt64] = [:]
        for apps in kept.values { for (app, t) in apps { totals[app, default: 0] &+= t.down &+ t.up } }
        if totals.count > maxApps {
            let top = Set(totals.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(maxApps).map(\.key))
            for (m, apps) in kept {
                let filtered = apps.filter { top.contains($0.key) }
                kept[m] = filtered.isEmpty ? nil : filtered
            }
        }
        return LiveUsageSnapshot(savedAt: savedAt, minutes: kept)
    }

    /// Kaydedilmiş kovaları mevcut geçmişe EKLER (açılışta ilk dakikalar çoktan ölçülmüş olabilir; zaman aralıkları ayrık).
    /// 60 dakikadan eski ve `nowMinute + 1`'den ilerideki (saat geri gitmiş) kovalar atılır.
    mutating func restore(_ snapshot: LiveUsageSnapshot, nowMinute: Int) {
        for (minute, apps) in snapshot.minutes where Self.isInWindow(minute, nowMinute: nowMinute) {
            for (app, t) in apps where !t.isEmpty { addMinute(minute, app: app, traffic: t) }
        }
    }

    private static func isInWindow(_ minute: Int, nowMinute: Int) -> Bool {
        minute > nowMinute - LiveRange.hour1.minutes && minute <= nowMinute + 1
    }

    private func minutesInWindow(nowMinute: Int) -> [Int: [String: LiveTraffic]] {
        allMinutes.filter { Self.isInWindow($0.key, nowMinute: nowMinute) }
    }
}

/// Anlık görüntü dosyası (Application Support/Adalmon/live-usage.snapshot). Tüm disk işi utility kuyruğunda;
/// ana iş parçacığı bloklanmaz (yalnızca çıkışta `saveBlocking`). Testler kendi geçici URL'sini verir.
final class LiveUsageSnapshotStore: @unchecked Sendable {
    let url: URL
    private let queue = DispatchQueue(label: "adalmon.live-usage-snapshot", qos: .utility)

    static var defaultURL: URL { AppEnvironment.supportDirectory.appending(path: "live-usage.snapshot") }

    init(url: URL = LiveUsageSnapshotStore.defaultURL) { self.url = url }

    /// Dosya yoksa ya da bozuksa `nil`. Bozuk dosya boş bir anlık görüntüyle üzerine yazılır (yeniden denenmez).
    func load() async -> LiveUsageSnapshot? {
        await withCheckedContinuation { c in queue.async { c.resume(returning: self.read()) } }
    }

    /// Geçmişin o anki hâlini arka planda yazar (`history` değer kopyasıdır; kodlama ana iş parçacığında yapılmaz).
    func save(history: LiveUsageHistory, nowMinute: Int, savedAt: Int) {
        queue.async { self.write(history.snapshot(nowMinute: nowMinute, savedAt: savedAt)) }
    }

    /// Çıkışta: bekleyen yazmalar bittikten sonra yazar ve döner.
    func saveBlocking(history: LiveUsageHistory, nowMinute: Int, savedAt: Int) {
        queue.sync { self.write(history.snapshot(nowMinute: nowMinute, savedAt: savedAt)) }
    }

    /// Kuyruktaki işlerin bitmesini bekler (testler).
    func waitUntilIdle() { queue.sync {} }

    private func read() -> LiveUsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let snapshot = LiveUsageSnapshot.decode(data) { return snapshot }
        write(LiveUsageSnapshot()) // bozuk: yok say ve geçerli boş dosyayla değiştir
        return nil
    }

    private func write(_ snapshot: LiveUsageSnapshot) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? snapshot.encoded().write(to: url, options: .atomic)
    }
}
