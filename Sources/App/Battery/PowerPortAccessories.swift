import Foundation
import IOKit

/// Mac'in USB‑C / Thunderbolt portlarına bağlı dış aksesuar (iPhone, harici SSD, ekran…).
///
/// Apple Silicon'da portlardan çıkan güç (PowerOut / watt) IORegistry'de OKUNAMIYOR: `IOAccessoryPowerCurrentLimits` sıfır,
/// `IOPortFeaturePowerSource` yalnızca fişten GELEN gücü (WinningPowerSourceOption) anlatır. Bu yüzden aksesuar ya hiç watt
/// göstermez (`allocatedMW == nil`) ya da USB host aygıtının ayrılmış akımından (`UsbPowerSinkAllocation`, mA × 5 V) türetilen
/// "≈" tahmini gösterir. Gerçek çekiş değildir.
struct PowerPortAccessory: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable { case phone, storage, display, hub, other }

    var id: String
    var name: String
    var kind: Kind
    /// "USB‑C 4".
    var portName: String
    /// "Realtek · DisplayPort".
    var detail: String
    /// USB host aygıtına ayrılan güç (mW, 5 V varsayımı); ölçüm değil.
    var allocatedMW: Int?
    /// Veri yolu yok (yalnız DisplayPort/CC): Mac'ten güç çektiği bilinmiyor.
    var isDisplayOnly = false
}

/// Saf: IORegistry sözlüklerinden aksesuar listesi. Testlerde sahte sözlüklerle beslenir.
enum PowerPortAccessoryParser {
    /// "Port-USB-C@4" → "USB‑C 4"; "Port-MagSafe 3@1" → "MagSafe 3".
    static func portName(_ description: String?) -> String? {
        guard var d = description, !d.isEmpty else { return nil }
        if d.hasPrefix("Port-") { d.removeFirst(5) }
        guard let at = d.lastIndex(of: "@") else { return d.replacingOccurrences(of: "-", with: "‑") }
        let base = d[..<at].replacingOccurrences(of: "-", with: "‑")
        let number = d[d.index(after: at)...]
        return base.contains("MagSafe") ? base : "\(base) \(number)"
    }

    static func kind(forName name: String) -> PowerPortAccessory.Kind {
        let n = name.lowercased()
        if n.contains("iphone") || n.contains("ipad") { return .phone }
        if n.contains("ssd") || n.contains("drive") || n.contains("disk") || n.contains("storage") || n.contains("card reader") { return .storage }
        if n.contains("hub") || n.contains("dock") { return .hub }
        if n.contains("display") || n.contains("monitor") { return .display }
        return .other
    }

    /// `ports`: AppleHPMInterface özellikleri + sentetik `_adapterSource` (Bool): bu portta kazanan güç kaynağı var (fiş).
    /// `usbDevices`: IOUSBHostDevice özellikleri.
    static func parse(ports: [[String: Any]], usbDevices: [[String: Any]]) -> [PowerPortAccessory] {
        var out: [PowerPortAccessory] = []
        let hasUSB = !usbDevices.isEmpty
        for p in ports {
            guard (p["ConnectionActive"] as? Bool) == true, (p["_adapterSource"] as? Bool) != true,
                  (p["PortTypeDescription"] as? String ?? "").contains("USB") else { continue }
            let transports = (p["TransportsActive"] as? [String]) ?? []
            let portName = portName(p["Description"] as? String) ?? "USB‑C"
            let mfg = (p["SOPMfgString"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let dataActive = transports.contains { $0.hasPrefix("USB") || $0 == "CIO" }
            let hasDP = transports.contains("DisplayPort")
            if !dataActive && !hasDP { continue } // yalnız CC: kablo ya da şarj aleti, gösterme.
            if dataActive && hasUSB { continue }  // veri yolu aygıtları USB listesinden gelir.
            let detail = [mfg, hasDP ? "DisplayPort" : nil, dataActive ? "USB" : nil].compactMap(\.self).joined(separator: " · ")
            out.append(PowerPortAccessory(
                id: "port." + portName, name: hasDP && !dataActive ? "Harici ekran" : "Aksesuar", kind: hasDP && !dataActive ? .display : .other,
                portName: portName, detail: detail, allocatedMW: nil, isDisplayOnly: !dataActive))
        }
        for d in usbDevices {
            guard let name = (d["USB Product Name"] as? String) ?? (d["kUSBProductString"] as? String), !name.isEmpty else { continue }
            let location = AppleSmartBatteryParser.int(d["locationID"]) ?? out.count
            // Ayrılan akım mA; 5 V varsayımıyla mW. Anahtar adı gerçek aygıtla doğrulanmadı (bkz. rapor).
            let mA = AppleSmartBatteryParser.int(d["UsbPowerSinkAllocation"]) ?? AppleSmartBatteryParser.int(d["kUSBWakePowerSupply"])
            let mfg = (d["USB Vendor Name"] as? String) ?? ""
            out.append(PowerPortAccessory(
                id: "usb.\(location)", name: name, kind: kind(forName: name), portName: "USB",
                detail: mfg.isEmpty ? "USB" : mfg + " · USB",
                allocatedMW: mA.flatMap { $0 > 0 ? $0 * 5 : nil }))
        }
        return out
    }
}

/// IOKit okuması. Yalnızca 5 sn'lik görünür döngüde ve olay anında çalışır; kare başına değil.
enum PowerPortAccessoryReader {
    struct Snapshot { var accessories: [PowerPortAccessory]; var adapterPortName: String? }

    static func read() -> Snapshot {
        var ports: [[String: Any]] = []
        var adapterPort: String?
        for cls in ["AppleHPMInterfaceType10", "AppleHPMInterfaceType11"] {
            var it: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &it) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(it) }
            while case let entry = IOIteratorNext(it), entry != 0 {
                defer { IOObjectRelease(entry) }
                var props: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      var d = props?.takeRetainedValue() as? [String: Any] else { continue }
                let winning = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, "WinningPowerSourceOption" as CFString,
                                                              kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) != nil
                d["_adapterSource"] = winning
                if winning { adapterPort = PowerPortAccessoryParser.portName(d["Description"] as? String) }
                ports.append(d)
            }
        }
        return Snapshot(accessories: PowerPortAccessoryParser.parse(ports: ports, usbDevices: usbDevices()), adapterPortName: adapterPort)
    }

    private static func usbDevices() -> [[String: Any]] {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &it) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }
        var out: [[String: Any]] = []
        while case let entry = IOIteratorNext(it), entry != 0 {
            defer { IOObjectRelease(entry) }
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let d = props?.takeRetainedValue() as? [String: Any] { out.append(d) }
        }
        return out
    }
}
