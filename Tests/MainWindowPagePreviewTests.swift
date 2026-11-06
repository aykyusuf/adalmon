import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Geçmiş ve Kurallar sayfalarını sahte veriyle ekran dışında çizip PNG yazar.
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class MainWindowPagePreviewTests: XCTestCase {
    func testRenderHistoryAndRules() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmp = FileManager.default.temporaryDirectory.appending(path: "prev-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = UsageStore(path: tmp.appending(path: "u.sqlite").path)
        await seed(store)

        try await render(HistoryPage(store: store), name: "history", dir: dir, size: NSSize(width: 800, height: 760))
        // Rapor: geniş pencerede yan yana (Dün kısayolu) ve çok günlük (Hafta).
        try await render(HistoryPage(store: store, initialRange: .day, initialOffset: 1), name: "history-report", dir: dir,
                         size: NSSize(width: 1400, height: 900))
        try await render(HistoryPage(store: store, initialRange: .week, initialOffset: 0), name: "history-report-week", dir: dir,
                         size: NSSize(width: 1400, height: 900))

        let suite = "adalmon.preview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        prefs.usageRules = Self.sampleRules
        prefs.tierLadder.enabled = true
        prefs.tierLadder.protectedApps = ["/System/Applications/Mail.app"]
        prefs.dataSaver.allowlist = ["/Applications/Safari.app"]
        let model = AppModel()
        let rules = VStack(alignment: .leading, spacing: 16) {
            RuleListSection(model: model, prefs: prefs, onEdit: { _ in }, onAdd: {})
            TierLadderSection(model: model, prefs: prefs)
            DataSaverSection(model: model, prefs: prefs)
        }
        .padding(24)
        try await render(rules, name: "rules", dir: dir, size: NSSize(width: 800, height: 1300))
        let r = Self.sampleRules
        let rows = VStack(spacing: 12) {
            RuleRow(rule: .constant(r[0]), status: RuleStatus(id: r[0].id, phase: .active, usedBytes: 620_000_000, thresholdBytes: 500_000_000,
                                                               windowStart: nil, windowEnd: nil, secondsUntilReset: 540, isEnforcedNow: true,
                                                               pendingFilterSupport: false), onEdit: {}, onDelete: {})
            RuleRow(rule: .constant(r[1]), status: RuleStatus(id: r[1].id, phase: .idle, usedBytes: 1_300_000_000, thresholdBytes: 4_000_000_000,
                                                               windowStart: .now, windowEnd: .now.addingTimeInterval(7_000), secondsUntilReset: 7_000,
                                                               isEnforcedNow: false, pendingFilterSupport: true), onEdit: {}, onDelete: {})
        }
        .padding(24)
        try await render(rows, name: "rule-rows", dir: dir, size: NSSize(width: 800, height: 330))
        try await render(RuleEditorSheet(model: model, draft: RuleDraft(rule: Self.sampleRules[0]), onSave: { _ in }), name: "rule-editor",
                   dir: dir, size: NSSize(width: 540, height: 640))
    }

    static let sampleRules = [
        UsageRule(name: "Safari kısıtı", app: "/Applications/Safari.app", scope: .mobileOnly,
                  trigger: .rolling(minutes: 10, bytes: 500_000_000), action: .throttle(downBytesPerSec: 256 * 1024, upBytesPerSec: nil)),
        UsageRule(name: "", app: "/System/Applications/Music.app", scope: .allNetworks,
                  trigger: .fixedWindow(hours: 3, bytes: 4_000_000_000), action: .block),
    ]

    private func seed(_ store: UsageStore) async {
        let cal = Calendar.current
        let dayStart = Int(cal.startOfDay(for: .now).timeIntervalSince1970)
        var items: [(hour: Int, mobile: UInt64, other: UInt64)] = []
        var rows: [UsageStore.HourlyRow] = []
        for h in 0..<14 {
            let m = UInt64((h * 37 % 11) + 1) * 8_000_000
            let w = UInt64((h * 53 % 13) + 2) * 25_000_000
            items.append((dayStart + h * 3_600, m, w))
            rows.append(UsageStore.HourlyRow(hour: dayStart + h * 3_600, app: "/Applications/Safari.app", domain: "YouTube", mobile: false, bytesIn: w * 6 / 10, bytesOut: 0))
            rows.append(UsageStore.HourlyRow(hour: dayStart + h * 3_600, app: "/System/Applications/Music.app", domain: "apple.com", mobile: true, bytesIn: m, bytesOut: 0))
        }
        await store.addInterfaceHourly(items)
        await store.add(day: "", rows: [], hourly: rows)
        // Günlük uygulama tablosu (rapor): son 10 gün, dünün özellikle zengin olması için.
        let apps = ["/Applications/Safari.app", "/System/Applications/Music.app", "/System/Applications/Mail.app", "/Applications/Xcode.app"]
        let hosts = ["rr1.googlevideo.com", "i.ytimg.com", "audio-ssl.itunes.apple.com", "imap.example.org", "developer.apple.com", "cdn.example.net"]
        for i in 0..<10 {
            let key = UsageStore.dayKey(Date.now.addingTimeInterval(-Double(i) * 86_400))
            var rows: [UsageStore.Row] = []
            for (a, app) in apps.enumerated() {
                for (h, host) in hosts.enumerated() where (a + h) % 2 == 0 {
                    rows.append(UsageStore.Row(app: app, host: host, mobile: (a + h + i) % 5 == 0,
                                               bytesIn: UInt64(40 + (a + 1) * (h + 2) * (12 - i)) * 9_000_000, bytesOut: 2_000_000))
                }
            }
            await store.add(day: key, rows: rows)
        }
        for i in 0..<30 {
            let key = UsageStore.dayKey(Date.now.addingTimeInterval(-Double(i) * 86_400))
            await store.addInterfaceBytes(day: key, mobile: true, bytes: UInt64(200 + i * 13 % 700) * 1_000_000)
            await store.addInterfaceBytes(day: key, mobile: false, bytes: UInt64(900 + i * 71 % 2_500) * 1_000_000)
        }
    }

    private func render<V: View>(_ view: V, name: String, dir: URL, size: NSSize) async throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -3000, y: -3000), size: size),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        // Görev/async yüklemelerin ana aktörde çalışabilmesi için bekleme askıya alınmalı (RunLoop değil).
        try await Task.sleep(for: .seconds(2))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = dir.appending(path: "\(name).png")
        try png.write(to: url)
        print("MAINWINDOW_PREVIEW: \(url.path())")
        window.close()
    }
}
