import Foundation

/// Kural motoru + kademeli limitin ürettiği, kullanıcının elle ayarlarıyla birleştirilmemiş katkılar.
struct RuleOutput: Equatable, Sendable {
    struct LimitContribution: Equatable, Sendable {
        var cause: RuleCause
        var limit: AppLimit
    }

    /// Uygulama anahtarı → etkin hız sınırı katkıları.
    var limits: [String: [LimitContribution]] = [:]
    /// Uygulama anahtarı → engel kaynakları (mobilde `blockedOnMobile` ile uygulanır).
    var blocked: [String: [RuleCause]] = [:]
    /// Her ağda (Wi-Fi dahil) engellenecek uygulamalar: "tüm ağlar" ENGEL kuralları + `allNetworks` kapsamlı merdiven kesmesi.
    /// `FilterConfig.blockedAlways` olarak filtreye gider (Faz B).
    var blockedAlways: Set<String> = []
    /// Faz B'de filtre bunu destekler; artık hiç set edilmez (UI/testler özelliği kullandığı için alan duruyor).
    var pendingFilterSupport: Set<UUID> = []
    var ladderPendingFilterSupport = false

    var isEmpty: Bool { limits.isEmpty && blocked.isEmpty && blockedAlways.isEmpty }
}
