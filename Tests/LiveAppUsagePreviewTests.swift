import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Opt-in PNGs of the live per-app list (Mobil + Ağ kullanımı) for visual sign-off.
/// Run with TEST_RUNNER_ADALMON_PREVIEW_DIR=<dir>. Hiçbir ağ kuralı uygulanmaz (sahte kontroller).
@MainActor
final class LiveAppUsagePreviewTests: XCTestCase {
    func testExportLiveListPreviews() throws {
        guard let path = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"] else { return }
        let dir = URL(filePath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let rows = [
            LiveAppUsage(app: "/Applications/Safari.app", down: 182_000_000, up: 4_100_000, rate: 2_400_000),
            LiveAppUsage(app: "/Applications/Google Chrome.app", down: 61_000_000, up: 2_300_000, rate: 310_000),
            LiveAppUsage(app: "/Applications/Xcode.app", down: 12_400_000, up: 900_000, rate: 0),
            LiveAppUsage(app: "/System/Library/PrivateFrameworks/CloudKitDaemon.framework/cloudd", down: 3_100_000, up: 1_200_000, rate: 12_000),
            LiveAppUsage(app: "/usr/libexec/nsurlsessiond", down: 900_000, up: 40_000, rate: 0),
            LiveAppUsage(app: "/Applications/Music.app", down: 500_000, up: 10_000, rate: 0),
            LiveAppUsage(app: "/Applications/Mail.app", down: 200_000, up: 30_000, rate: 0),
        ]
        let limits: [String: AppLimit] = ["/Applications/Google Chrome.app": AppLimit(downBytesPerSec: 1_048_576, upBytesPerSec: 1_048_576, onlyOnMobile: true)]
        let blocked: Set<String> = ["/Applications/Xcode.app"]
        let controls = LiveAppControls(limit: { limits[$0] }, blockScope: { blocked.contains($0) ? .everywhere : nil }, setLimit: { _, _ in }, setBlockScope: { _, _ in })

        let mobile = LiveAppUsageList(title: "Mobil veriyi şu an kullananlar", source: .fixed(rows), controls: controls,
                                      interfaces: [.mobile], maxRows: 6, limitsOnlyOnMobile: true, initialRange: .min15, initialRows: rows)
            .padding(24).frame(width: 900)
        let network = LiveAppUsageList(source: .fixed(rows), controls: controls, maxRows: 5, initialRows: rows)
            .padding(24).frame(width: 900)
        let narrow = LiveAppUsageList(source: .fixed(rows), controls: controls, maxRows: 5, compact: true, initialRows: rows)
            .padding(16).frame(width: 560)
        let empty = LiveAppUsageList(title: "Mobil veriyi şu an kullananlar", source: .fixed([]), controls: controls,
                                     interfaces: [.mobile], limitsOnlyOnMobile: true)
            .padding(24).frame(width: 900)
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            try MenuBarSettingsSnapshotTestsAccess.snapshot(mobile, dark: dark, size: NSSize(width: 900, height: 470),
                                                            to: dir.appending(path: "canli-mobil-\(suffix).png"))
            try MenuBarSettingsSnapshotTestsAccess.snapshot(network, dark: dark, size: NSSize(width: 900, height: 420),
                                                            to: dir.appending(path: "canli-ag-\(suffix).png"))
        }
        try MenuBarSettingsSnapshotTestsAccess.snapshot(narrow, dark: false, size: NSSize(width: 560, height: 380),
                                                        to: dir.appending(path: "canli-ag-dar.png"))
        try MenuBarSettingsSnapshotTestsAccess.snapshot(empty, dark: false, size: NSSize(width: 900, height: 160),
                                                        to: dir.appending(path: "canli-mobil-bos.png"))
    }
}
