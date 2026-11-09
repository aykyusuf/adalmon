import Foundation

/// Arka plan işlemi satırının metinleri (panel, ofis kartı ve testler aynı biçimi kullanır). Yalnızca ad, süre, CPU ve bellek.
struct SessionShellRowModel: Equatable, Identifiable, Sendable {
    var id: Int32
    var name: String
    var age: String
    var cpu: String
    var ram: String

    init(_ shell: SessionShell) {
        id = shell.pid
        name = shell.name
        age = SessionShellFormat.age(seconds: shell.ageSeconds)
        cpu = SessionShellFormat.cpu(shell.cpuPercent)
        ram = SessionShellFormat.memory(shell.rssBytes)
    }
}

enum SessionShellFormat {
    static let footnote = "Yalnızca işlem adı gösterilir"

    /// "45 sn", "2 dk", "1 sa 5 dk".
    static func age(seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s) sn" }
        let m = s / 60
        if m < 60 { return "\(m) dk" }
        let h = m / 60, rest = m % 60
        return rest == 0 ? "\(h) sa" : "\(h) sa \(rest) dk"
    }

    static func cpu(_ percent: Double) -> String {
        percent < 10 ? String(format: "%%%.1f", percent).replacingOccurrences(of: ".", with: ",") : "%\(Int(percent.rounded()))"
    }

    static func memory(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb < 1024 ? "\(Int(mb.rounded())) MB" : String(format: "%.1f GB", mb / 1024).replacingOccurrences(of: ".", with: ",")
    }

    /// Bölüm başlığı: "Arka plan işlemleri (N)".
    static func title(total: Int) -> String { "Arka plan işlemleri (\(total))" }
    /// Listede gösterilmeyenler için "+K daha".
    static func more(_ hidden: Int) -> String? { hidden > 0 ? "+\(hidden) daha" : nil }
}
