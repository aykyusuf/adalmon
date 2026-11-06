/// Uygulama anahtarının (bundle ya da çalıştırılabilir yol) türü; ikon seçimini belirler.
enum AppKind: Sendable, Equatable {
    /// `.app` paketi: paketin kendi ikonu.
    case application
    /// Komut satırı aracı (curl, node, dartvm …): terminal rozeti.
    case commandLineTool
    /// Sistem servisi / arka plan süreci (nsurlsessiond, mDNSResponder …): dişli rozeti.
    case systemService
}
