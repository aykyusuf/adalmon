import AppKit
import Darwin
import Foundation
import Security

/// Bir sürecin ayrıntılarını libproc / Security çerçevesinden okur. Yalnızca "Bilgi" açılınca çağrılır.
enum ProcessDetailsReader {
    static func read(pid: pid_t) -> ProcessDetails {
        var d = ProcessDetails(pid: pid)
        d.path = CoalitionAPI.path(of: pid)
        var bsd = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize {
            d.parentPID = Int32(bsd.pbi_ppid)
            d.user = userName(uid: bsd.pbi_uid)
            d.startDate = Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec) + TimeInterval(bsd.pbi_start_tvusec) / 1e6)
            d.isSuspended = bsd.pbi_status == UInt32(SSTOP)
        }
        var task = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
        if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize { d.threads = Int(task.pti_threadnum) }
        let fdBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        if fdBytes > 0 { d.openFiles = Int(fdBytes) / MemoryLayout<proc_fdinfo>.size }
        d.nice = ProcessActions.nice(of: pid)
        d.isEfficient = ProcessActions.isEfficient(pid: pid)
        d.coalitionID = CoalitionAPI.coalitionID(of: pid)
        if let path = d.path { fillSignature(&d, path: path) }
        return d
    }

    @MainActor
    static func architecture(of pid: pid_t) -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        switch app.executableArchitecture {
        case NSBundleExecutableArchitectureARM64: return "Apple silicon (arm64)"
        case NSBundleExecutableArchitectureX86_64: return "Intel (x86_64)"
        default: return nil
        }
    }

    private static func userName(uid: UInt32) -> String? {
        guard let pw = getpwuid(uid) else { return "uid \(uid)" }
        return String(cString: pw.pointee.pw_name)
    }

    private static func fillSignature(_ d: inout ProcessDetails, path: String) {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(filePath: AppNaming.outermostApp(of: path)) as CFURL, [], &code) == errSecSuccess, let code else { return }
        d.isSigned = SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return }
        d.signingIdentifier = dict[kSecCodeInfoIdentifier as String] as? String
        d.teamIdentifier = dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
