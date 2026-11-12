import SwiftUI
import XCTest
@testable import Adalmon

/// Temizlik > Başlangıç ekranı açık/koyu PNG olarak (sahte veri; gerçek launchctl çağrılmaz).
@MainActor
final class StartupPreviewTests: XCTestCase {
    private func items() -> [StartupItem] {
        [
            StartupItem(label: "com.spotify.webhelper", name: "Spotify", plistPath: "/Users/demo/Library/LaunchAgents/com.spotify.webhelper.plist",
                        program: "/Applications/Spotify.app/Contents/MacOS/Spotify", scope: .user, status: .enabled, runsAtLoad: true),
            StartupItem(label: "com.old.updater", name: "Eski Güncelleyici", plistPath: "/Users/demo/Library/LaunchAgents/com.old.updater.plist",
                        program: "/Applications/Old.app/Contents/MacOS/updater", scope: .user, status: .enabled, runsAtLoad: true,
                        problem: .programMissing("/Applications/Old.app/Contents/MacOS/updater")),
            StartupItem(label: "com.figma.agent", name: "Figma Agent", plistPath: "/Users/demo/Library/LaunchAgents/com.figma.agent.plist",
                        program: "/Applications/Figma.app/Contents/MacOS/agent", scope: .user, status: .disabled, runsAtLoad: true),
            StartupItem(label: "com.vendor.helper", name: "Vendor Helper", plistPath: "/Library/LaunchAgents/com.vendor.helper.plist",
                        program: "/Library/Vendor/helper", scope: .allUsers, status: .enabled, runsAtLoad: true),
            StartupItem(label: "com.vendor.daemon", name: "Vendor Daemon", plistPath: "/Library/LaunchDaemons/com.vendor.daemon.plist",
                        program: "/Library/Vendor/daemon", scope: .daemon, status: .enabled, runsAtLoad: true),
        ]
    }

    private func background() -> [BackgroundItem] {
        [BackgroundItem(id: "b1", name: "Dropbox", detail: "Dropbox Updater", developer: "Dropbox, Inc.", identifier: "com.dropbox.updater", kind: .agent, isEnabled: true),
         BackgroundItem(id: "b2", name: "Rectangle", detail: nil, developer: "Ryan Hanson", identifier: "com.knollsoft.Rectangle", kind: .loginItem, isEnabled: false)]
    }

    func testRenderStartupStates() throws {
        let dir = try RD3PreviewRender.previewDir()
        for dark in [false, true] {
            let full = StartupItemsModel(scan: { [items = items()] in items }, scanBackground: { [bg = background()] in bg })
            try RD3PreviewRender.render(StartupCleanupView(model: full), prefix: "startup", name: "1-list", dark: dark, dir: dir, height: 900)
            let narrow = StartupItemsModel(scan: { [items = items()] in items }, scanBackground: { [bg = background()] in bg })
            try RD3PreviewRender.render(StartupCleanupView(model: narrow), prefix: "startup", name: "2-list-narrow", dark: dark, dir: dir,
                                        width: 560, height: 900)
            let empty = StartupItemsModel(scan: { [] }, scanBackground: { [] })
            try RD3PreviewRender.render(StartupCleanupView(model: empty), prefix: "startup", name: "3-empty", dark: dark, dir: dir)
        }
    }
}
