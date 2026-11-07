import Foundation

/// "Bilgi" sayfası için bir sürecin ayrıntıları. Okunamayan alan nil (başka kullanıcının süreçleri).
struct ProcessDetails: Equatable, Sendable {
    var pid: Int32
    var path: String?
    var parentPID: Int32?
    var user: String?
    var startDate: Date?
    var threads: Int?
    var openFiles: Int?
    var nice: Int32?
    var coalitionID: UInt64?
    var architecture: String?
    var signingIdentifier: String?
    var teamIdentifier: String?
    var isSigned: Bool?
    var isSuspended = false
    var isEfficient = false

    func uptime(now: Date = .now) -> TimeInterval? { startDate.map { max(0, now.timeIntervalSince($0)) } }
}
