import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Güç akışı: önizleme PNG'leri (`ADALMON_PREVIEW_DIR` ile) + çizim maliyeti ölçümü.
@MainActor
final class PowerFlowPreviewTests: XCTestCase {
    private var previewDir: URL? {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else { return nil }
        return URL(filePath: env)
    }

    private func charging() -> BatteryReading {
        var r = BatteryReading.sampleCharging
        r.systemPowerMW = 52_300; r.batteryPowerMW = 38_400; r.systemLoadMW = 13_900
        r.adapterVoltageMV = 20_000; r.adapterCurrentMA = 3_390; r.adapterEfficiencyLossMW = 2_100
        r.systemVoltageInMV = 20_204; r.systemCurrentInMA = 2_589; r.adapterPortName = "MagSafe 3"
        return r
    }

    private func full() -> BatteryReading {
        var r = charging()
        r.level = 100; r.isCharging = false; r.isFullyCharged = true; r.amperageMA = 0
        r.systemPowerMW = 36_439; r.batteryPowerMW = 0; r.systemLoadMW = 36_439; r.adapterEfficiencyLossMW = 948
        return r
    }

    private func onBattery() -> BatteryReading {
        var r = BatteryReading.sample
        r.systemPowerMW = 0; r.batteryPowerMW = -15_800; r.systemLoadMW = 15_800
        return r
    }

    private func card(_ model: PowerFlowModel, phase: Double, reduceMotion: Bool = false) -> some View {
        PowerFlowView(model: model, forceAnimating: false, fixedPhase: reduceMotion ? nil : phase, forceReduceMotion: reduceMotion)
            .padding(14)
            .frame(width: 520)
            .background(Color(white: 0.16))
            .environment(\.colorScheme, .dark)
    }

    private func render<V: View>(_ view: V, name: String) throws {
        guard let dir = previewDir else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: dir.appending(path: "\(name).png"))
        print("PF_PREVIEW: \(dir.appending(path: "\(name).png").path())")
    }

    func testRenderPreviews() throws {
        try render(card(PowerFlowModel.make(charging()), phase: 6), name: "pf-charging")
        try render(card(PowerFlowModel.make(full()), phase: 6), name: "pf-full")
        try render(card(PowerFlowModel.make(onBattery()), phase: 6), name: "pf-battery")
        var withDevices = charging()
        withDevices.accessories = [
            PowerPortAccessory(id: "usb.1", name: "iPhone", kind: .phone, portName: "USB‑C 2", detail: "Apple · USB", allocatedMW: 7_500),
            PowerPortAccessory(id: "usb.2", name: "Portable SSD", kind: .storage, portName: "USB‑C 3", detail: "USB", allocatedMW: nil)]
        try render(card(PowerFlowModel.make(withDevices), phase: 6), name: "pf-devices")
        try render(card(PowerFlowModel.make(charging()), phase: 0, reduceMotion: true), name: "pf-reduce-motion")
    }

    /// 2 sn @ 30 fps = 60 kare: yalnız kenar Canvas'ının CPU çizimi (ImageRenderer ile). Gerçek ekrandaki GPU/CA commit maliyetini
    /// KAPSAMAZ; üst sınır niteliğinde bir vekil (ImageRenderer yazılımla rasterize eder).
    /// Entegrasyon: panel "Pil bilgisi" içeriği ve Pil sayfası kartı (statik kare).
    func testIntegrationPreviews() throws {
        var r = charging()
        r.accessories = [PowerPortAccessory(id: "usb.1", name: "iPhone", kind: .phone, portName: "USB‑C 2", detail: "Apple · USB", allocatedMW: 7_500)]
        let model = BatteryPanelModel.make(r, lastRefresh: .now)
        let blocks = VStack(alignment: .leading, spacing: 10) { BatteryInfoBlocks(model: model, actions: .inert) }
            .padding(12).frame(width: 540).background(Color(white: 0.16)).environment(\.colorScheme, .dark)
        try render(blocks, name: "pf-panel-info")
        let page = ChartCard(title: "Güç akışı", symbol: "bolt.circle", trailing: { Text("Adaptör bağlı").font(.callout).foregroundStyle(.secondary) },
                             footer: "Adaptör Mac'e ve (şarj oluyorsa) pile dağılır; kalınlık ve hız watt ile orantılı.") {
            PowerFlowView(model: PowerFlowModel.make(r), forceAnimating: false, fixedPhase: 5)
        }
        .padding(16).frame(width: 900).background(Color(white: 0.11)).environment(\.colorScheme, .dark)
        try render(page, name: "pf-page-card")
    }

    /// Gerçek makinede (read-only IOKit): model üretilir, aksesuarlar listelenir.
    func testLiveReadingBuildsModel() throws {
        guard let r = BatteryReader.read() else { throw XCTSkip("dahili pil yok") }
        let m = PowerFlowModel.make(r)
        print("PF_LIVE: mod=\(m.mode) edges=\(m.edges.map { "\($0.kind.rawValue)=\($0.label)" }) accessories=\(r.accessories.map { "\($0.name)/\($0.portName)/\($0.detail)" }) port=\(r.adapterPortName ?? "-")")
        print("PF_LIVE: \(m.summary)")
        XCTAssertFalse(m.nodes.isEmpty)
    }

    func testEdgeDrawingTwoSecondLoopStaysCheap() throws {
        var r = charging()
        r.accessories = [PowerPortAccessory(id: "usb.1", name: "iPhone", kind: .phone, portName: "USB‑C 2", detail: "", allocatedMW: 7_500)]
        let model = PowerFlowModel.make(r)
        let clock = FlowClock()
        let frames = 60
        var perFrame: [Double] = []
        var signatures = Set<Int>()
        var t = Date(timeIntervalSince1970: 100)
        for _ in 0..<frames {
            t = t.addingTimeInterval(1.0 / 30)
            clock.advance(to: t, edges: model.edges)
            let phases = clock.phases
            let view = Canvas { ctx, size in PowerFlowCanvas.draw(&ctx, size: size, model: model, phases: phases, motion: .dots, hovered: nil) }
                .frame(width: 500, height: PowerFlowModel.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let start = DispatchTime.now().uptimeNanoseconds
            let image = try XCTUnwrap(renderer.cgImage)
            let data = image.dataProvider?.data // piksellerin gerçekten üretilmesi (lazy olabilir) ölçüme dahil
            perFrame.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            if let data { signatures.insert((data as Data).hashValue) }
        }
        let total = perFrame.reduce(0, +)
        let avg = total / Double(frames)
        print("PF_BENCH: \(frames) kare toplam \(String(format: "%.1f", total)) ms, ort \(String(format: "%.2f", avg)) ms/kare, en kötü \(String(format: "%.2f", perFrame.max() ?? 0)) ms, 30 fps'te vekil CPU ≈ %\(String(format: "%.1f", avg * 30 / 10))")
        XCTAssertGreaterThan(signatures.count, 30, "kareler gerçekten farklı çizilmeli (noktalar hareket ediyor)")
        XCTAssertLessThan(avg, 8, "kare başı yazılım çizimi bütçesi")
        // Boşta (aktif kenar yok) ya da gizliyken hiç çizim yok: model tarafı.
        XCTAssertFalse(PowerFlowModel.make(BatteryReading(isPluggedIn: true, isFullyCharged: false)).hasMotion)
    }
}
