import AppKit
import SpriteKit
import XCTest
@testable import Adalmon

/// Ofis duvar kâğıdı önizlemesi: 3840x2160 ve 2560x1440 ekranlarda 1/3/10 oturum, gündüz + gece, PNG + düğüm/bellek ölçümü.
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class OfficeWallpaperPreviewTests: XCTestCase {
    private let models = ["claude-opus-4-8", "claude-sonnet-5-5", "claude-haiku-4-5", "claude-fable-1"]
    private let types = ["scanner", "deep-reader", "implementer", "implementer-hard", "reviewer", "ui-tester", "Explore", "Plan"]

    private func session(_ i: Int, subs n: Int) -> AgentSession {
        let now = Date()
        let st: [AgentStatus] = [.tool("Bash"), .thinking, .idle, .tool("Read"), .waitingPermission, .tool("Grep"), .idle, .tool("Edit")]
        let subs = (0..<n).map { k in
            AgentSubagent(agentID: "s\(i)-\(k)", agentType: types[(k + i) % types.count], model: models[(k + 1) % models.count], status: st[(k + i) % st.count],
                          activity: "Bash", target: "build.sh", activityAt: now)
        }
        var s = AgentSession(id: "sess-\(i)", project: ["adalmon", "terra-app", "site", "api-core", "docs", "infra", "mobile", "ml-lab", "billing", "web"][i % 10],
                             model: models[i % models.count], status: i % 3 == 0 ? .thinking : (i % 3 == 1 ? .tool("Edit") : .idle),
                             startedAt: now.addingTimeInterval(-600), lastEventAt: now, subagents: subs, activity: "Edit", target: "main.swift", activityAt: now)
        s.title = ["Duvar kâğıdı ofisi", "Faturalama düzeltmesi", "Site yenileme", "API sürüm", "Dokümantasyon", "Altyapı", "Mobil", "Model eğitimi", "Raporlar", "Web"][i % 10]
        return s
    }

    private func render(_ sessions: [AgentSession], pixels: CGSize, night: Bool, labels: OfficeLabelPolicy = .auto, background: OfficeWallpaperBackground = .dark,
                        theme: OfficeTheme = .vector) throws -> (CGImage, OfficeScene) {
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let points = CGSize(width: pixels.width / 2, height: pixels.height / 2)   // Retina: 2 piksel / pt
        let view = SKView(frame: CGRect(origin: .zero, size: points))
        let scene = OfficeScene(assets: assets, size: points, theme: theme)
        let c = background.rgb
        scene.backgroundColor = SKColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        scene.wallpaperLabels = labels
        view.presentScene(scene)
        scene.setLightingMode(night ? .night : .day, animated: false)
        scene.apply(members: OfficeMember.members(from: sessions), animated: false)
        let tex = try XCTUnwrap(view.texture(from: scene))
        let img = tex.cgImage()
        scene.shutdown()
        return (img, scene)
    }

    private func write(_ cg: CGImage, _ name: String, dir: URL) throws {
        let rep = NSBitmapImageRep(cgImage: cg)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "\(name).png"))
    }

    func testRenderWallpaper() throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else { throw XCTSkip("ADALMON_PREVIEW_DIR yok") }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sets: [(String, [AgentSession])] = [("s1", [session(0, subs: 4)]),
                                                ("s3", (0..<3).map { session($0, subs: [3, 1, 5][$0]) }),
                                                ("s10", (0..<10).map { session($0, subs: [2, 0, 4, 1, 3, 0, 2, 1, 5, 2][$0]) })]
        for (res, px) in [("4k", CGSize(width: 3840, height: 2160)), ("1440", CGSize(width: 2560, height: 1440))] {
            for (name, sessions) in sets {
                for night in [false, true] {
                    let (img, scene) = try render(sessions, pixels: px, night: night)
                    let tag = "\(res)-\(name)-\(night ? "night" : "day")"
                    try write(img, tag, dir: dir)
                    print("OFFICEWALL \(tag) img=\(img.width)x\(img.height) zoom=\(scene.zoom) rooms=\(scene.roomCount) nodes=\(scene.nodeCount)")
                }
            }
        }
        // Boş durum + açık arka plan + etiket seçenekleri
        let (empty, _) = try render([], pixels: CGSize(width: 3840, height: 2160), night: false)
        try write(empty, "4k-empty-day", dir: dir)
        let (emptyNight, _) = try render([], pixels: CGSize(width: 3840, height: 2160), night: true)
        try write(emptyNight, "4k-empty-night", dir: dir)
        let (light, _) = try render(sets[1].1, pixels: CGSize(width: 3840, height: 2160), night: false, background: .light)
        try write(light, "4k-s3-day-lightbg", dir: dir)
        let (always, _) = try render(sets[2].1, pixels: CGSize(width: 2560, height: 1440), night: false, labels: .always)
        try write(always, "1440-s10-day-labelsalways", dir: dir)
        let (pixel, _) = try render(sets[1].1, pixels: CGSize(width: 3840, height: 2160), night: false, theme: .pixel)
        try write(pixel, "4k-s3-day-pixel", dir: dir)
    }

    /// Bellek bütçesi: ikinci bir sahne örneğinin ek kalıcı bellek maliyeti (ana pencere sahnesi + duvar kâğıdı sahnesi).
    func testMemoryOfSecondScene() throws {
        guard ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"]?.isEmpty == false else { throw XCTSkip("ADALMON_PREVIEW_DIR yok") }
        let assets = try XCTUnwrap(OfficeAssets.shared)
        func mb() -> Double {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
            _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
            return Double(info.resident_size) / 1_048_576
        }
        let sessions = (0..<5).map { session($0, subs: 4) }
        let points = CGSize(width: 1920, height: 1080)
        let v1 = SKView(frame: CGRect(origin: .zero, size: points))
        let s1 = OfficeScene(assets: assets, size: points, theme: .vector)
        v1.presentScene(s1); s1.apply(members: OfficeMember.members(from: sessions), animated: false)
        _ = v1.texture(from: s1)
        let base = mb()
        let v2 = OfficeWallpaperView(frame: CGRect(origin: .zero, size: points))
        let s2 = OfficeScene(assets: assets, size: points, theme: .vector)
        s2.wallpaperLabels = .auto
        v2.presentScene(s2); s2.apply(members: OfficeMember.members(from: sessions), animated: false)
        _ = v2.texture(from: s2)
        let withSecond = mb()
        print("OFFICEWALL memory base=\(Int(base))MB withSecondScene=\(Int(withSecond))MB delta=\(Int(withSecond - base))MB nodes=\(s2.nodeCount)")
        s2.shutdown(); v2.presentScene(nil)
        s1.shutdown(); v1.presentScene(nil)
    }
}
