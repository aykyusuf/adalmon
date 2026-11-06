import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Ana pencere bölümlerini sahte veriyle ekran dışı bir pencerede çizip PNG yazar.
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class MainWindowPreviewTests: XCTestCase {
    func testRenderMainWindowSections() throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let limits = ["/System/Applications/Music.app": AppLimit(downBytesPerSec: 1_000_000, upBytesPerSec: 200_000, onlyOnMobile: true)]
        let model = AppModel()
        for section in MainSection.allCases {
            let router = SettingsRouter(isDockModeOn: { true })
            router.selectedMainSection = section
            let view = MainWindowView(data: .sample, limits: limits, actions: .inert, router: router) { settings in
                SettingsDetailView(section: settings, model: model)
            }
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 1000, height: 680),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            let url = dir.appending(path: "main-\(section.id).png")
            try png.write(to: url)
            print("MAINWINDOW_PREVIEW: \(url.path())")
            window.close()
        }
    }
}
