import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Her preset'i açık ve koyu görünümde PNG'ye çizer (görsel kontrol için).
/// Hedef klasör: `ADALMON_PREVIEW_DIR` (xcodebuild'e `TEST_RUNNER_ADALMON_PREVIEW_DIR=...` ile verilir), yoksa geçici klasör.
final class MenuBarPreviewExportTests: XCTestCase {
    func testExportPresetPreviews() throws {
        let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"]
        let dir = URL(filePath: env ?? NSTemporaryDirectory()).appending(path: env == nil ? "menubar-previews" : "")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var outputs: [(name: String, config: MenuBarConfig)] = MenuBarPreset.allCases.map { ($0.rawValue, $0.makeConfig()) }
        outputs.append(("all-library", Self.allLibraryConfig))
        outputs.append(("simple-default", .default))
        for layout in MetricLayout.allCases {
            var cards = [MetricCardConfig(.cpu, shown: true, fields: [.cpu, .cpuTemp], layout: layout),
                         MetricCardConfig(.memory, shown: true, fields: [.memoryUsed], layout: layout),
                         MetricCardConfig(.network, shown: true, fields: [.download, .upload], layout: layout)]
            outputs.append(("layout-\(layout.rawValue)", MenuBarConfig(components: MetricCardConfig.components(for: cards))))
            cards = [MetricCardConfig(.cpu, shown: true, fields: [.cpu, .cpuTemp], showGraph: true, layout: layout, thresholdColor: true),
                     MetricCardConfig(.gpu, shown: true, fields: [.gpu, .gpuTemp], layout: layout, thresholdColor: true),
                     MetricCardConfig(.memory, shown: true, fields: [.memoryUsed, .memoryFree, .memoryPercent], layout: layout),
                     MetricCardConfig(.disk, shown: true, fields: [.diskFree, .diskPercent], layout: layout),
                     MetricCardConfig(.mobile, shown: true, fields: [.mobileUsed, .mobileRemaining], layout: layout),
                     MetricCardConfig(.temperature, shown: true, fields: [.ssdTemp, .batteryTemp], layout: layout)]
            outputs.append(("layout-\(layout.rawValue)-all", MenuBarConfig(components: MetricCardConfig.components(for: cards))))
        }

        for (name, config) in outputs {
            for (suffix, appearance, background) in [
                ("dark", NSAppearance.Name.darkAqua, NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)),
                ("light", NSAppearance.Name.aqua, NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)),
            ] {
                let image = MenuBarComposer.image(for: config.enabledComponents, config: config, values: .sample, appearance: appearance)
                let url = dir.appending(path: "\(name)-\(suffix).png")
                try Self.png(image, background: background).write(to: url)
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path()))
                print("MENUBAR_PREVIEW: \(url.path())")
            }
        }
    }

    /// Ayarlar penceresindeki önizleme bölümünün (maket + açıklama) ekran görüntüsü benzeri PNG'leri.
    @MainActor
    func testExportLibraryGridAndEditorMock() throws {
        // SwiftUI renders are opt-in (TEST_RUNNER_ADALMON_PREVIEW_DIR=<dir> xcodebuild test ...): ImageRenderer of these
        // views can report a runtime issue that hangs XCTest symbolication in this environment.
        guard ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"] != nil else { return }
        let dir = Self.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = MenuBarPreset.ayrintili.makeConfig()
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "" : "-light"
            let grid = ComponentLibraryGrid(config: config, values: .sample) { _ in }
                .padding(18)
                .frame(width: 780)
                .background(scheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
                .environment(\.colorScheme, scheme)
            try Self.write(grid, to: dir.appending(path: "library-grid\(suffix).png"))

            var selected = config.components[0]
            selected.colorMode = .threshold
            let editor = VStack(alignment: .leading, spacing: 14) {
                MenuBarEditorMock(config: config, values: .sample, selection: .constant(config.components[0].id),
                                  zoom: 1.5, interactive: false)
                MenuBarEditorMock(config: config, values: .sample, selection: .constant(config.components[1].id), dark: false,
                                  zoom: 1, interactive: false)
                Text("Görünüm").font(.headline)
                VisualChips(component: .constant(selected), config: config, values: .sample)
                Text("Renk").font(.headline)
                ColorModePicker(component: .constant(selected))
                Text("Hazır düzenler").font(.headline)
                PresetStrip(config: config, values: .sample, current: .ayrintili, scrolls: false) { _ in }
            }
            .padding(18)
            .frame(width: 900)
            .background(scheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
            .environment(\.colorScheme, scheme)
            try Self.write(editor, to: dir.appending(path: "editor-mock\(suffix).png"))
        }
    }

    @MainActor
    private static func write(_ view: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("MENUBAR_PREVIEW_FAILED: \(url.lastPathComponent)")
            return
        }
        try png.write(to: url)
        print("MENUBAR_PREVIEW: \(url.path())")
    }

    private static func outputDirectory() -> URL {
        let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"]
        return URL(filePath: env ?? NSTemporaryDirectory()).appending(path: env == nil ? "menubar-previews" : "")
    }

    /// Her metrik için desteklediği tüm stiller (stil kataloğu görseli).
    private static var allLibraryConfig: MenuBarConfig {
        MenuBarConfig(components: ComponentLibrary.entries.map(\.component), spacing: 8)
    }

    private static func png(_ image: NSImage, background: NSColor, scale: CGFloat = 3, padding: CGFloat = 8) throws -> Data {
        let size = NSSize(width: image.size.width + padding * 2, height: image.size.height + padding)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw CocoaError(.fileWriteUnknown)
        }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        background.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(x: padding, y: padding / 2, width: image.size.width, height: image.size.height))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
