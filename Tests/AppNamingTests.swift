import XCTest
@testable import Adalmon

final class AppNamingTests: XCTestCase {
    private func name(_ key: String, bundle: String? = nil) -> String {
        AppNaming.identity(forApp: key, bundleName: { _ in bundle }).name
    }
    private func kind(_ key: String) -> AppKind { AppNaming.identity(forApp: key).kind }

    func testSystemDaemons() {
        XCTAssertEqual(name("/usr/libexec/nsurlsessiond"), "Arka plan indirmeleri (nsurlsessiond)")
        XCTAssertEqual(name("/usr/sbin/mDNSResponder"), "DNS (sistem)")
        XCTAssertEqual(name("/System/Library/PrivateFrameworks/ApplePushService.framework/apsd"), "Apple Push")
        XCTAssertEqual(name("/usr/libexec/softwareupdated"), "Yazılım güncelleme")
        XCTAssertEqual(name("/System/Library/PrivateFrameworks/CloudKitDaemon.framework/Support/cloudd"), "iCloud")
        XCTAssertEqual(name("/System/Library/PrivateFrameworks/DataAccess.framework/Support/dataaccessd"), "Takvim/Kişiler eşitleme")
        XCTAssertEqual(name("/System/Library/PrivateFrameworks/HelpData.framework/Versions/A/Resources/helpd"), "Yardım (sistem)")
        XCTAssertEqual(name("/usr/libexec/rapportd"), "Yakındaki aygıtlar")
        XCTAssertEqual(name("/usr/libexec/trustd"), "Sertifika denetimi")
        XCTAssertEqual(kind("/usr/libexec/nsurlsessiond"), .systemService)
    }

    func testDottedExecutableNamesKeepTheirSuffix() {
        XCTAssertEqual(name("/System/Library/PrivateFrameworks/SafariSafeBrowsing.framework/Versions/A/com.apple.Safari.SafeBrowsing.Service"),
                       "Safari güvenli tarama")
    }

    func testBundleNameDirectionMarksAreStripped() {
        XCTAssertEqual(name("/Applications/WhatsApp.app", bundle: "\u{200E}WhatsApp"), "WhatsApp")
    }

    func testUnknownSystemDaemonGetsSystemSuffix() {
        XCTAssertEqual(name("/usr/libexec/ciphermld"), "ciphermld (sistem)")
        XCTAssertEqual(kind("/usr/libexec/ciphermld"), .systemService)
    }

    func testWebKitNetworkingFallsBackToSafariWebKitWithoutMerging() {
        for p in ["/System/Volumes/Preboot/Cryptexes/Incoming/OS/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.Networking.xpc",
                  "/System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.Networking.xpc"] {
            let id = AppNaming.identity(forApp: p)
            XCTAssertEqual(id.name, "Safari / WebKit")
            XCTAssertEqual(id.iconBundleID, "com.apple.Safari")
            XCTAssertEqual(id.kind, .systemService)
        }
    }

    func testCommandLineTools() {
        XCTAssertEqual(name("/usr/bin/curl"), "curl")
        XCTAssertEqual(name("/opt/homebrew/Cellar/gh/2.88.1/bin/gh"), "GitHub CLI")
        XCTAssertEqual(name("/opt/homebrew/Cellar/deno/2.9.7/bin/deno"), "Deno")
        XCTAssertEqual(name("/opt/homebrew/Cellar/asc/5.7.0/bin/asc"), "asc")
        XCTAssertEqual(name("/opt/homebrew/Cellar/gplay/1.0.0/bin/gplay"), "gplay")
        XCTAssertEqual(name("/usr/bin/git"), "Git")
        XCTAssertEqual(name("/usr/bin/ssh"), "SSH")
        XCTAssertEqual(name("/opt/homebrew/bin/brew"), "Homebrew")
        XCTAssertEqual(name("/opt/homebrew/bin/ollama"), "Ollama")
        XCTAssertEqual(name("/opt/homebrew/bin/python3.14"), "Python")
        XCTAssertEqual(name("/usr/bin/python3"), "Python")
        XCTAssertEqual(kind("/usr/bin/curl"), .commandLineTool)
        XCTAssertEqual(kind("/opt/homebrew/Cellar/asc/5.7.0/bin/asc"), .commandLineTool)
    }

    func testClaudeCodeVersionedBinary() {
        XCTAssertEqual(name("/Users/u/.local/share/claude/versions/2.1.318"), "Claude Code")
        XCTAssertEqual(kind("/Users/u/.local/share/claude/versions/2.1.318"), .commandLineTool)
        XCTAssertEqual(name("/opt/homebrew/bin/claude"), "Claude Code")
        XCTAssertEqual(name("/Users/u/tools/mytool/versions/1.2.3"), "mytool")
    }

    func testDartAndFlutterTools() {
        XCTAssertEqual(name("/Users/u/.shorebird/bin/cache/flutter/ff900e7/bin/cache/dart-sdk/bin/dartvm"), "Dart VM (Flutter)")
        XCTAssertEqual(name("/Users/u/fvm/versions/3.41.9/bin/cache/dart-sdk/bin/dart"), "Dart (Flutter)")
        XCTAssertEqual(name("/Users/u/Development/flutter/bin/cache/dart-sdk/bin/dart"), "Dart (Flutter)")
        XCTAssertEqual(name("/opt/homebrew/bin/dart"), "Dart")
    }

    func testRaycastToolsAreTagged() {
        XCTAssertEqual(name("/Users/u/Library/Application Support/com.raycast.macos/node/runtime/node-v26/bin/node"), "Node.js (Raycast)")
        XCTAssertEqual(name("/Users/u/Library/Application Support/com.raycast.macos/extensions/x/cli/speedtest"), "Speedtest (Raycast)")
    }

    func testAppBundlesUseBundleNameThenFileStem() {
        XCTAssertEqual(name("/Applications/Ollama 2.app", bundle: "Ollama"), "Ollama")
        XCTAssertEqual(name("/Applications/Google Chrome.app"), "Google Chrome")
        XCTAssertEqual(name("/Applications/WhatsApp.app", bundle: ""), "WhatsApp")
        XCTAssertEqual(kind("/Applications/Google Chrome.app"), .application)
        XCTAssertEqual(name("/opt/homebrew/Cellar/python@3.14/3.14.8/Frameworks/Python.framework/Versions/3.14/Resources/Python.app", bundle: "Python"), "Python")
    }

    func testSystemHelperAppOverrides() {
        XCTAssertEqual(name("/System/Library/Frameworks/AddressBook.framework/Versions/A/Helpers/AddressBookSourceSync.app", bundle: "AddressBookSourceSync"), "Kişiler eşitleme")
        XCTAssertEqual(name("/System/Library/PrivateFrameworks/IMTransferServices.framework/IMTransferAgent.app"), "iMessage dosya aktarımı")
        XCTAssertEqual(name("/Users/u/Library/Application Support/Setapp/LaunchAgents/SetappUpdater.app", bundle: "SetappUpdater"), "Setapp Güncelleyici")
    }

    func testHelpersRollUpToParentApp() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        XCTAssertEqual(AppNaming.outermostApp(of: helper), "/Applications/Google Chrome.app")
        XCTAssertEqual(name(helper, bundle: "Google Chrome"), "Google Chrome")
        XCTAssertEqual(AppNaming.outermostApp(of: "/Applications/Foo.app"), "/Applications/Foo.app")
        XCTAssertEqual(AppNaming.outermostApp(of: "/usr/bin/curl"), "/usr/bin/curl")
    }

    func testStripHelperSuffix() {
        XCTAssertEqual(AppNaming.stripHelperSuffix("Google Chrome Helper"), "Google Chrome")
        XCTAssertEqual(AppNaming.stripHelperSuffix("Slack Helper (Renderer)"), "Slack")
        XCTAssertEqual(AppNaming.stripHelperSuffix("Code Helper (GPU)"), "Code")
        XCTAssertEqual(AppNaming.stripHelperSuffix("Helper Tools"), "Helper Tools")
        XCTAssertEqual(AppNaming.stripHelperSuffix("Helpers Inc"), "Helpers Inc")
        XCTAssertEqual(name("/Library/PrivilegedHelperTools/Foo Helper.app", bundle: "Foo Helper"), "Foo")
    }

    func testDisplayLayerNeverChangesKey() {
        // Eşleştirme (limit/engel) anahtarı AppCatalog'a hiç girmez; ad yalnızca gösterim içindir.
        let key = "/usr/libexec/nsurlsessiond"
        _ = AppNaming.identity(forApp: key)
        XCTAssertEqual(key, "/usr/libexec/nsurlsessiond")
    }

    @MainActor
    func testCatalogIconsExistForEveryKind() {
        let c = AppCatalog.shared
        for key in ["/usr/bin/curl", "/usr/libexec/nsurlsessiond", "/Applications/Does Not Exist.app", "/System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.Networking.xpc"] {
            XCTAssertGreaterThan(c.icon(for: key).size.width, 0, key)
        }
        XCTAssertEqual(c.name(for: "/usr/bin/curl"), "curl")
    }
}
