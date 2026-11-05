import Foundation
import Network
import Observation

/// Bağlantı durumu: Wi-Fi mi, mobil veri (iPhone hotspot / USB tethering) mi.
@MainActor @Observable
final class PathMonitor {
    enum Medium: Equatable { case wifi, ethernet, cellular, other, offline }

    private(set) var isExpensive = false
    private(set) var isConstrained = false
    private(set) var medium: Medium = .other
    private(set) var interfaceName = ""

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let exp = path.isExpensive
            let con = path.isConstrained
            let iface = path.availableInterfaces.first { path.usesInterfaceType($0.type) }
            let medium: Medium
            if path.status != .satisfied { medium = .offline }
            else if path.usesInterfaceType(.wifi) { medium = .wifi }
            else if path.usesInterfaceType(.cellular) { medium = .cellular }
            else if path.usesInterfaceType(.wiredEthernet) { medium = .ethernet }
            else { medium = .other }
            let name = iface?.name ?? ""
            Task { @MainActor in
                guard let self else { return }
                self.isExpensive = exp
                self.isConstrained = con
                self.medium = medium
                self.interfaceName = name
            }
        }
        monitor.start(queue: DispatchQueue(label: "adalmon.path"))
    }

    /// iPhone hotspot (Wi-Fi/USB) macOS tarafından "expensive" işaretlenir.
    func isMobile(force: Bool) -> Bool { force || isExpensive || isConstrained || medium == .cellular }
}
