import XCTest
@testable import Adalmon

final class BrowserProcessNamingTests: XCTestCase {
    private let safari = "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"
    private let chrome = "/Applications/Google Chrome.app"

    func testSafariProcesses() {
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "com.apple.WebKit.WebContent", groupKey: safari), "Web İçeriği (sekme)")
        XCTAssertEqual(BrowserProcessNaming.match(rawName: "com.apple.WebKit.WebContent", groupKey: safari)?.role, .tab)
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "com.apple.WebKit.GPU", groupKey: safari), "Grafik (GPU) süreci")
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "com.apple.WebKit.Networking", groupKey: safari), "Ağ süreci")
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "Safari", groupKey: safari), "Safari (ana süreç)")
    }

    func testChromeProcessesIncludingAperitifVariant() {
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "Google Chrome Helper (Renderer)", groupKey: chrome), "Sekme (renderer)")
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "Google Chrome Helper (Aperitif Renderer)", groupKey: chrome), "Sekme (renderer)")
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "Google Chrome Helper (GPU)", groupKey: chrome), "Grafik (GPU) süreci")
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "Google Chrome Helper (Plugin)", groupKey: chrome), "Eklenti süreci")
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "Google Chrome Helper (Aperitif)", groupKey: chrome), "Yardımcı (Aperitif)")
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "Google Chrome Helper", groupKey: chrome), "Yardımcı süreç")
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "Google Chrome", groupKey: chrome), "Google Chrome (ana süreç)")
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "Microsoft Edge Helper (Renderer)", groupKey: "/Applications/Microsoft Edge.app"), "Sekme (renderer)")
    }

    func testUnknownAndForeignNamesStayAsIs() {
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "VTDecoderXPCService", groupKey: safari), "VTDecoderXPCService")
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "Safari", groupKey: "/Applications/Other.app"), "Safari", "başka uygulamanın 'Safari' adlı süreci değişmez")
        XCTAssertEqual(BrowserProcessNaming.display(rawName: "node", groupKey: "/usr/local/bin/node"), "node")
    }
}
