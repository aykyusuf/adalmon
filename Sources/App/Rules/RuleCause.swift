import Foundation

/// Bir sınırın ya da engelin kaynağı (UI "hangi kural yüzünden" için).
enum RuleCause: Hashable, Sendable {
    case rule(UUID)
    case ladder(TierLevel)
}
