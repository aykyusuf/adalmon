import AppKit
import Darwin
import Foundation

/// Süreçler sayfasının eylemleri: sonlandırma kuralları, sinyal gönderme, Finder, panoya kopyalama.
enum ProcessActions {
    /// Bu süreci (benim kullanıcım, Adalmon'un kendisi değil) sonlandırabilir miyiz? Başka kullanıcının süreçleri için
    /// `proc_pidinfo` EPERM döner; onlar sonlandırılamaz.
    static func isKillable(pid: pid_t) -> Bool {
        guard pid > 1, pid != getpid() else { return false }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_uid == getuid()
    }

    static func killablePIDs(_ pids: [pid_t]) -> [pid_t] { pids.filter(isKillable(pid:)) }

    /// Kalan canlı süreçler (sinyal 0 ile yoklama).
    static func alive(_ pids: [pid_t]) -> [pid_t] { pids.filter { kill($0, 0) == 0 } }

    @discardableResult
    static func terminate(_ pids: [pid_t]) -> Int { pids.reduce(0) { $0 + (kill($1, SIGTERM) == 0 ? 1 : 0) } }

    @discardableResult
    static func forceKill(_ pids: [pid_t]) -> Int { pids.reduce(0) { $0 + (kill($1, SIGKILL) == 0 ? 1 : 0) } }

    // MARK: Askıya alma / öncelik / verimlilik

    @discardableResult
    static func suspend(_ pids: [pid_t]) -> Int { pids.reduce(0) { $0 + (kill($1, SIGSTOP) == 0 ? 1 : 0) } }

    @discardableResult
    static func resume(_ pids: [pid_t]) -> Int { pids.reduce(0) { $0 + (kill($1, SIGCONT) == 0 ? 1 : 0) } }

    static func isStopped(pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_status == UInt32(SSTOP)
    }

    /// nice değeri; okunamazsa nil.
    static func nice(of pid: pid_t) -> Int32? {
        errno = 0
        let value = getpriority(PRIO_PROCESS, id_t(pid))
        return value == -1 && errno != 0 ? nil : value
    }

    @discardableResult
    static func setNice(_ pids: [pid_t], to value: Int32) -> Int {
        pids.reduce(0) { $0 + (setpriority(PRIO_PROCESS, id_t($1), value) == 0 ? 1 : 0) }
    }

    /// Verimlilik modu = Darwin arka plan öncelik sınıfı (düşük CPU/G/Ç/ağ önceliği, E çekirdeklere yönlenir).
    /// Başka bir sürece `setpriority` "harici" arka plan bayrağı koyar (PROC_FLAG_EXT_DARWINBG); kendi sürecimizde `getpriority` 1 döner.
    static func isEfficient(pid: pid_t) -> Bool {
        if getpriority(PRIO_DARWIN_PROCESS, id_t(pid)) == 1 { return true }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_flags & (0x8000 | 0x10000) != 0 // PROC_FLAG_DARWINBG | PROC_FLAG_EXT_DARWINBG (mach/task_policy.h)
    }

    @discardableResult
    static func setEfficiency(_ pids: [pid_t], on: Bool) -> Int {
        pids.reduce(0) { $0 + (setpriority(PRIO_DARWIN_PROCESS, id_t($1), on ? PRIO_DARWIN_BG : 0) == 0 ? 1 : 0) }
    }

    /// Satırın süreçlerinin toplu durumu (en çok 32 süreç yoklanır).
    static func state(of pids: [pid_t]) -> ProcessStateSummary {
        ProcessStateSummary(items: pids.prefix(32).map {
            let owned = isKillable(pid: $0)
            return .init(isOwned: owned, isStopped: owned && isStopped(pid: $0), isEfficient: owned && isEfficient(pid: $0))
        })
    }

    // MARK: Uygulama / örnek

    /// Çalışan uygulamayı nazikçe (`terminate`) ya da zorla (`forceTerminate`) kapatır. Uygulama bulunamazsa false.
    @MainActor
    static func terminateApplication(bundlePath: String, force: Bool) -> Bool {
        let url = URL(filePath: bundlePath).standardizedFileURL
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL == url && $0.processIdentifier != getpid() }
        guard !running.isEmpty else { return false }
        for app in running { _ = force ? app.forceTerminate() : app.terminate() }
        return true
    }

    /// `/usr/bin/sample <pid> 3` çıktısını ~/Library/Logs/Adalmon/ altına yazar. Senkron (3 sn); arka planda çağır.
    nonisolated static func sampleProcess(pid: pid_t, name: String) -> URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Adalmon", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let stamp = Int(Date().timeIntervalSince1970)
        let out = dir.appending(path: "sample-\(safe.isEmpty ? "process" : safe)-\(pid)-\(stamp).txt")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/sample")
        process.arguments = [String(pid), "3", "-file", out.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: out.path) ? out : nil
    }

    @MainActor
    static func searchWeb(for name: String) {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: "\(name) macOS process")]
        if let url = components?.url { NSWorkspace.shared.open(url) }
    }

    /// "Yeni görev çalıştır": uygulama seçtirip açar.
    @MainActor
    static func runNewTask() {
        let panel = NSOpenPanel()
        panel.title = "Yeni görev çalıştır"
        panel.prompt = "Çalıştır"
        panel.allowedContentTypes = [.application, .unixExecutable]
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { NSLog("Adalmon: görev başlatılamadı: \(error.localizedDescription)") }
        }
    }

    @MainActor
    static func reveal(path: String) {
        guard path.hasPrefix("/") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
    }

    @MainActor
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
