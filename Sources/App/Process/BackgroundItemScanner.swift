import Foundation

enum BackgroundItemScanner {
    /// `sfltool dumpbtm` root gerektirmeden çalışır ama ~7 sn sürebilir; yalnızca ihtiyaç olunca, ana iş parçacığı dışında çağırın.
    /// Başarısız olursa boş döner (arayüz Sistem Ayarları bağlantısına düşer).
    static func scan(uid: uid_t = getuid()) async -> [BackgroundItem] {
        let result = await CommandRunner.run("/usr/bin/sfltool", ["dumpbtm"], timeout: 30)
        guard result.succeeded else { return [] }
        return BackgroundItemParser.parse(result.output, uid: uid)
    }
}
