import Foundation

/// nice değeri değişikliği: root olmadan yalnızca artırılabilir (önceliği düşürmek); azaltmak root ister. Saf mantık.
enum ProcessPriorityPlan: Equatable, Sendable {
    case apply(Int32)
    case noChange
    case needsRoot

    static let presets: [(title: String, nice: Int32)] = [("Normal", 0), ("Düşük", 10), ("En düşük", 19)]

    static func evaluate(currentNice: Int32, target: Int32) -> ProcessPriorityPlan {
        if target == currentNice { return .noChange }
        return target > currentNice ? .apply(target) : .needsRoot
    }
}
