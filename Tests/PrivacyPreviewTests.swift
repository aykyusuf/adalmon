import SwiftUI
import XCTest
@testable import Adalmon

/// Gizlilik sihirbazı ekranları açık/koyu PNG olarak (sahte veri). Yalnızca ADALMON_PREVIEW_DIR verilince çalışır.
@MainActor
final class PrivacyPreviewTests: XCTestCase {
    private let home = "/Users/demo"

    private func file(_ browser: String, _ name: String, _ kind: PrivacyDataKind, kb: Int, ino: UInt64) -> PrivacyFile {
        PrivacyFile(path: "/Users/demo/Library/\(browser)/Default/\(name)", kind: kind, profile: "Default", bytes: UInt64(kb) << 10, dev: 1, ino: ino)
    }

    private func scans(edgeRunning: Bool = false, empty: Bool = false) -> [BrowserPrivacyScan] {
        if empty {
            return PrivacyBrowser.allCases.map { BrowserPrivacyScan(browser: $0, state: .scanned, profileCount: 1) }
        }
        let chrome = BrowserPrivacyScan(browser: .chrome, state: .scanned, profileCount: 2, files: [
            file("Chrome", "History", .history, kb: 48_000, ino: 1), file("Chrome", "Top Sites", .history, kb: 600, ino: 2),
            file("Chrome", "Cookies", .cookies, kb: 3_200, ino: 3),
        ])
        let edge = edgeRunning
            ? BrowserPrivacyScan(browser: .edge, state: .running)
            : BrowserPrivacyScan(browser: .edge, state: .scanned, profileCount: 1, files: [
                file("Edge", "History", .history, kb: 12_000, ino: 4), file("Edge", "Cookies", .cookies, kb: 900, ino: 5),
            ])
        let safari = BrowserPrivacyScan(browser: .safari, state: .noAccess)
        return [chrome, edge, safari]
    }

    private func makeVM(_ scans: [BrowserPrivacyScan]? = nil, select: Bool = false) -> BrowserPrivacyViewModel {
        let vm = BrowserPrivacyViewModel(home: home, runningBundleIDs: { [] })
        if let scans {
            vm.apply(scans)
            if select {
                vm.toggle(.history, in: .chrome)
                vm.toggle(.cookies, in: .chrome)
                if vm.scan(for: .edge)?.state == .scanned { vm.toggle(.history, in: .edge) }
            }
        }
        return vm
    }

    func testRenderPrivacyStates() throws {
        let dir = try RD3PreviewRender.previewDir()
        for dark in [false, true] {
            try RD3PreviewRender.render(PrivacySection(vm: makeVM()), prefix: "privacy", name: "1-welcome", dark: dark, dir: dir)
            try RD3PreviewRender.render(PrivacySection(vm: makeVM(), forceScanning: true), prefix: "privacy", name: "2-scanning", dark: dark, dir: dir)
            try RD3PreviewRender.render(PrivacySection(vm: makeVM(scans(), select: true)), prefix: "privacy", name: "3-result", dark: dark, dir: dir)
            try RD3PreviewRender.render(PrivacySection(vm: makeVM(scans(edgeRunning: true), select: true)),
                                        prefix: "privacy", name: "3b-result-open-browser", dark: dark, dir: dir)
            try RD3PreviewRender.render(PrivacySection(vm: makeVM(scans(), select: true)), prefix: "privacy", name: "3c-result-narrow",
                                        dark: dark, dir: dir, width: 560, height: 700)
            let freed = PrivacyFreed(count: 5, bytes: 64_700 << 10, skipped: [], mode: .trash)
            try RD3PreviewRender.render(PrivacySection(vm: makeVM(scans(), select: false), startFreed: freed),
                                        prefix: "privacy", name: "4-done", dark: dark, dir: dir)
            try RD3PreviewRender.render(PrivacySection(vm: makeVM(scans(empty: true))), prefix: "privacy", name: "5-allclean", dark: dark, dir: dir)
        }
    }
}
