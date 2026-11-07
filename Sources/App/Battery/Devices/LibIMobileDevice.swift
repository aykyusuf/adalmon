import Foundation

/// libimobiledevice (LGPL-2.1+) ve libplist'in çalışma zamanında `dlopen` ile yüklenen C API'si.
/// Kitaplıklar `Adalmon.app/Contents/Frameworks` içinde paketlidir; yoksa (ya da yüklenemezse) `load()` nil döner
/// ve iPhone/iPad ayrıntıları sessizce kapalı kalır. Başlık dosyası yok; imzalar include/libimobiledevice/*.h'den elle yazıldı.
final class LibIMobileDevice: @unchecked Sendable {
    typealias Handle = OpaquePointer
    typealias ListFn = @convention(c) (UnsafeMutablePointer<UnsafeMutablePointer<UnsafeMutableRawPointer?>?>, UnsafeMutablePointer<Int32>) -> Int32
    typealias ListFreeFn = @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
    typealias NewFn = @convention(c) (UnsafeMutablePointer<Handle?>, UnsafePointer<CChar>?, Int32) -> Int32
    typealias FreeFn = @convention(c) (Handle?) -> Int32
    typealias HandshakeFn = @convention(c) (Handle?, UnsafeMutablePointer<Handle?>, UnsafePointer<CChar>?) -> Int32
    typealias GetValueFn = @convention(c) (Handle?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutablePointer<Handle?>) -> Int32
    typealias StartDiagFn = @convention(c) (Handle?, UnsafeMutablePointer<Handle?>, UnsafePointer<CChar>?) -> Int32
    typealias QueryIORegFn = @convention(c) (Handle?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutablePointer<Handle?>) -> Int32
    typealias ToXMLFn = @convention(c) (Handle?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>, UnsafeMutablePointer<UInt32>) -> Int32
    typealias PlistFreeFn = @convention(c) (Handle?) -> Void
    typealias MemFreeFn = @convention(c) (UnsafeMutableRawPointer?) -> Void

    static let imobiledeviceName = "libimobiledevice-1.0.6.dylib"
    static let plistName = "libplist-2.0.12.dylib"

    let deviceList: ListFn
    let deviceListFree: ListFreeFn
    let deviceNew: NewFn
    let deviceFree: FreeFn
    let lockdownHandshake: HandshakeFn
    let lockdownFree: FreeFn
    let lockdownGetValue: GetValueFn
    let diagnosticsStart: StartDiagFn
    let diagnosticsQuery: QueryIORegFn
    let diagnosticsGoodbye: FreeFn
    let diagnosticsFree: FreeFn
    let plistToXML: ToXMLFn
    let plistFree: PlistFreeFn
    let memFree: MemFreeFn

    private init?(imobiledevice: UnsafeMutableRawPointer, plist: UnsafeMutableRawPointer) {
        func sym<T>(_ lib: UnsafeMutableRawPointer, _ name: String, as _: T.Type) -> T? {
            guard let p = dlsym(lib, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let a = sym(imobiledevice, "idevice_get_device_list_extended", as: ListFn.self),
              let b = sym(imobiledevice, "idevice_device_list_extended_free", as: ListFreeFn.self),
              let c = sym(imobiledevice, "idevice_new_with_options", as: NewFn.self),
              let d = sym(imobiledevice, "idevice_free", as: FreeFn.self),
              let e = sym(imobiledevice, "lockdownd_client_new_with_handshake", as: HandshakeFn.self),
              let f = sym(imobiledevice, "lockdownd_client_free", as: FreeFn.self),
              let g = sym(imobiledevice, "lockdownd_get_value", as: GetValueFn.self),
              let h = sym(imobiledevice, "diagnostics_relay_client_start_service", as: StartDiagFn.self),
              let i = sym(imobiledevice, "diagnostics_relay_query_ioregistry_entry", as: QueryIORegFn.self),
              let j = sym(imobiledevice, "diagnostics_relay_goodbye", as: FreeFn.self),
              let k = sym(imobiledevice, "diagnostics_relay_client_free", as: FreeFn.self),
              let l = sym(plist, "plist_to_xml", as: ToXMLFn.self),
              let m = sym(plist, "plist_free", as: PlistFreeFn.self),
              let n = sym(plist, "plist_mem_free", as: MemFreeFn.self) else { return nil }
        (deviceList, deviceListFree, deviceNew, deviceFree, lockdownHandshake, lockdownFree, lockdownGetValue) = (a, b, c, d, e, f, g)
        (diagnosticsStart, diagnosticsQuery, diagnosticsGoodbye, diagnosticsFree, plistToXML, plistFree, memFree) = (h, i, j, k, l, m, n)
    }

    /// Paketlenmiş kopyayı (ya da geliştirme için Homebrew kopyasını) yükler. Bulunamazsa nil.
    static func load(frameworksDirectory: String? = Bundle.main.privateFrameworksPath) -> LibIMobileDevice? {
        var dirs: [String] = []
        if let frameworksDirectory { dirs.append(frameworksDirectory) }
        #if DEBUG
        // Geliştirme kolaylığı: paket dışı Homebrew kopyası (hardened runtime kitaplık doğrulaması imzasız kopyayı reddedebilir).
        dirs.append(contentsOf: ["/opt/homebrew/lib", "/usr/local/lib"])
        #endif
        for dir in dirs {
            let main = dir + "/" + imobiledeviceName
            guard FileManager.default.fileExists(atPath: main),
                  let plistLib = dlopen(dir + "/" + plistName, RTLD_NOW | RTLD_LOCAL) ?? dlopen(dir + "/libplist-2.0.dylib", RTLD_NOW | RTLD_LOCAL),
                  let lib = dlopen(main, RTLD_NOW | RTLD_LOCAL),
                  let loaded = LibIMobileDevice(imobiledevice: lib, plist: plistLib) else { continue }
            return loaded
        }
        return nil
    }

    // MARK: plist yardımcıları

    /// plist düğümünü Swift sözlüğüne çevirir (XML üzerinden) ve düğümü serbest bırakır.
    func dictionary(consuming node: Handle?) -> [String: Any]? {
        guard let node else { return nil }
        defer { plistFree(node) }
        var xml: UnsafeMutablePointer<CChar>?
        var length: UInt32 = 0
        guard plistToXML(node, &xml, &length) == 0, let xml else { return nil }
        defer { memFree(xml) }
        let data = Data(bytes: xml, count: Int(length))
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
