import CoreGraphics
import SpriteKit
import XCTest
@testable import Adalmon

/// Vektör karakter: kare üretici sözleşmesi, parametre eşlemeleri, önbellek, etiket/balon düzeni ve web atlası şeması.
@MainActor
final class OfficeVectorCharacterTests: XCTestCase {
    private typealias VC = OfficeVectorCharacter

    private func bytes(_ img: CGImage) -> [UInt8] { OfficePixels(cgImage: img)?.data ?? [] }

    func testEveryLookDirectionFrameRenders() throws {
        for look in 0..<VC.looks.count {
            for d in OfficeCharacterSheet.Direction.allCases {
                for f in 0..<VC.frameCount {
                    let img = try XCTUnwrap(VC.frame(look: look, direction: d, frameIndex: f), "look \(look) \(d) kare \(f)")
                    XCTAssertEqual(img.width, VC.canvasW * 4)
                    XCTAssertEqual(img.height, VC.canvasH * 4)
                    let px = bytes(img)
                    XCTAssertGreaterThan(px.enumerated().filter { $0.offset % 4 == 3 && $0.element > 0 }.count, 600, "boş kare \(look)/\(d)/\(f)")
                    XCTAssertEqual(px[3], 0, "köşe saydam olmalı")
                }
            }
        }
    }

    func testLeftIsMirrorOfRight() throws {
        for f in [0, 1, 3, 13] {
            let r = try XCTUnwrap(OfficePixels(cgImage: try XCTUnwrap(VC.frame(look: 2, direction: .right, frameIndex: f))))
            let l = try XCTUnwrap(OfficePixels(cgImage: try XCTUnwrap(VC.frame(look: 2, direction: .left, frameIndex: f))))
            let flipped = r.flippedHorizontally()
            var diff = 0
            for i in 0..<flipped.data.count where abs(Int(flipped.data[i]) - Int(l.data[i])) > 6 { diff += 1 }
            XCTAssertLessThan(diff, flipped.data.count / 200, "sol = sağın yansıması (kare \(f))")
        }
    }

    func testPosesDiffer() throws {
        func img(_ f: Int) throws -> [UInt8] { bytes(try XCTUnwrap(VC.frame(look: 0, direction: .up, frameIndex: f))) }
        XCTAssertNotEqual(try img(3), try img(4), "yazma kareleri farklı")
        XCTAssertNotEqual(try img(1), try img(0), "yürüme ≠ ayakta")
        XCTAssertNotEqual(try img(1), try img(9), "el kaldırma ≠ ayakta")
        XCTAssertNotEqual(try img(1), try img(12), "uyuklama ≠ ayakta")
    }

    func testLookTable() {
        XCTAssertEqual(VC.looks.count, 6)
        XCTAssertEqual(Set(VC.looks.map(\.style)).count, 6, "6 farklı saç stili")
        XCTAssertEqual(VC.skinTones.count, 6)
        XCTAssertEqual(Set(VC.looks.map(\.skin)).count, 6)
    }

    func testModelToLookMapping() {
        XCTAssertEqual(OfficeAppearance.appearance(for: .opus).characterIndex, 2)
        XCTAssertEqual(OfficeAppearance.appearance(for: .sonnet).characterIndex, 0)
        XCTAssertEqual(OfficeAppearance.appearance(for: .haiku).characterIndex, 4)
        XCTAssertEqual(OfficeAppearance.appearance(for: .fable).characterIndex, 5)
        XCTAssertEqual(OfficeAppearance.appearance(for: .unknown).characterIndex, 3)
        XCTAssertEqual(VC.spec(for: OfficeAppearance.appearance(for: .opus)).model, "crown")
        XCTAssertEqual(VC.spec(for: OfficeAppearance.appearance(for: .sonnet)).model, "cap")
        XCTAssertEqual(VC.spec(for: OfficeAppearance.appearance(for: .haiku)).model, "sprout")
        XCTAssertEqual(VC.spec(for: OfficeAppearance.appearance(for: .fable)).model, "star")
    }

    func testRoleToOutfitMapping() {
        let m = OfficeMember(id: "a", parentID: "p", kind: .subagent, label: "implementer-hard", badge: .haiku, status: .thinking, groupIndex: 0)
        let s = VC.spec(for: OfficeAppearance.appearance(for: m))
        XCTAssertEqual(s.look, 4, "model look korunur")
        XCTAssertEqual(s.shirt, 0x8E4FE0)
        XCTAssertEqual(s.role, "headphones")
        XCTAssertTrue(s.hoodie)
        XCTAssertEqual(s.model, "none", "alt ajanda model aksesuarı yok")
        let r = OfficeMember(id: "b", parentID: "p", kind: .subagent, label: "ui-smoke", badge: .sonnet, status: .idle, groupIndex: 0)
        XCTAssertEqual(VC.spec(for: OfficeAppearance.appearance(for: r)).role, "vest")
    }

    func testCacheKeys() {
        let a = VC.Spec(look: 0, shirt: 0x112233)
        var b = a; b.role = "glasses"
        var c = a; c.hoodie = true
        var d = a; d.prop = .cleaner
        XCTAssertEqual(Set([a.key, b.key, c.key, d.key]).count, 4)
        XCTAssertEqual(a.key, VC.Spec(look: 0, shirt: 0x112233).key)
    }

    func testTextureCacheIsLazyAndShared() throws {
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let look = OfficeAppearance.appearance(for: .sonnet)
        let before = assets.vectorCharacterFrameCount
        let t1 = assets.characterTexture(for: look, direction: .up, frame: 3, theme: .vector)
        let t2 = assets.characterTexture(for: look, direction: .up, frame: 3, theme: .vector)
        let tl = assets.characterTexture(for: look, direction: .left, frame: 3, theme: .vector)
        let tr = assets.characterTexture(for: look, direction: .right, frame: 3, theme: .vector)
        XCTAssertTrue(t1 === t2)
        XCTAssertTrue(tl === tr, "sol, sağ dokuyu paylaşır (düğüm yansıtır)")
        XCTAssertLessThanOrEqual(assets.vectorCharacterFrameCount - before, 2)
        XCTAssertEqual(t1.size(), CGSize(width: 96, height: 128))
    }

    func testNightGradeBrightens() throws {
        let day = try XCTUnwrap(VC.frame(look: 0, direction: .down, frameIndex: 1))
        let night = VC.nightGrade(day)
        func sum(_ i: CGImage) -> Int { bytes(i).reduce(0) { $0 + Int($1) } }
        XCTAssertGreaterThan(sum(night), sum(day))
        XCTAssertEqual(night.width, day.width)
    }

    func testVectorBubbleGeometry() throws {
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let tb = OfficeTextBubble(theme: .vector)
        tb.setText("Bash çalıştırıyor", assets: assets)
        XCTAssertEqual(tb.height, OfficeVectorUI.bubbleHeight)
        XCTAssertEqual(tb.tailX, OfficeVectorUI.bubbleTipX)
        XCTAssertGreaterThanOrEqual(tb.width, OfficeVectorUI.bubbleMinBody)
        XCTAssertNotNil(tb.background.texture)
        let px = OfficeTextBubble(theme: .pixel)
        XCTAssertEqual(px.height, OfficeTextBubble.height)
        XCTAssertEqual(px.tailX, OfficePixelArt.speechBubbleTailX)
    }

    func testVectorRoomLabelsAndNoAccessoryNodes() throws {
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let scene = OfficeScene(assets: assets, size: CGSize(width: 900, height: 700), theme: .vector)
        let now = Date()
        let s = AgentSession(id: "s", project: "p", model: "claude-opus-4-8", status: .tool("Edit"), startedAt: now, lastEventAt: now,
                             subagents: [AgentSubagent(agentID: "a", agentType: "reviewer", model: "claude-sonnet-5-5", status: .tool("Bash"), activity: "Bash", target: "x", activityAt: now)],
                             activity: "Edit", target: "m.swift", activityAt: now)
        scene.apply(members: OfficeMember.members(from: [s]), animated: false)
        let room = try XCTUnwrap(scene.room(scene.roomIDs[0]))
        room.setLabels(true)
        XCTAssertFalse(room.actors.isEmpty)
        for a in room.actors.values {
            XCTAssertNil(a.roleAccessory, "vektör: rol aksesuarı gövdeye pişirilmiş")
            XCTAssertNil(a.accessory)
            XCTAssertNotNil(a.labelPill)
            XCTAssertEqual(a.body.size, CGSize(width: 24, height: 32))
        }
        scene.shutdown()
    }

    func testAtlasJSONSchemaAndSize() throws {
        let j = VC.atlasJSON()
        XCTAssertEqual(j["scale"] as? Int, 4)
        XCTAssertEqual(j["frameCount"] as? Int, 18)
        XCTAssertEqual((j["looks"] as? [[String: Any]])?.count, 6)
        XCTAssertEqual((j["roles"] as? [[String: Any]])?.count, OfficeRoles.knownKeys.count)
        XCTAssertEqual((j["models"] as? [[String: Any]])?.count, AgentModelBadge.allCases.count)
        let atlas = try XCTUnwrap(j["atlas"] as? [String: Any])
        let index = try XCTUnwrap(atlas["index"] as? [[String: Int]])
        XCTAssertEqual(index.count, 6 * 3 * 18)
        XCTAssertEqual(atlas["width"] as? Int, 18 * 96)
        XCTAssertEqual(atlas["height"] as? Int, 18 * 128)
        let last = try XCTUnwrap(index.last)
        XCTAssertEqual(last["x"], 17 * 96); XCTAssertEqual(last["y"], 17 * 128)
        let acc = try XCTUnwrap(j["accessories"] as? [String: Any])
        XCTAssertEqual((acc["index"] as? [[String: Any]])?.count, VC.accessoryItems.count * 3)
        let sizes = ["image", "mask"].map { (atlas[$0] as? String)?.count ?? 0 } + [(acc["image"] as? String)?.count ?? 0]
        print("ATLAS uri bayt: renk=\(sizes[0]) maske=\(sizes[1]) aksesuar=\(sizes[2])")
        XCTAssertTrue((atlas["image"] as? String)?.hasPrefix("data:image/png;base64,") == true)
        XCTAssertLessThan(sizes.reduce(0, +), 1_600_000, "karakter atlası ≤ ~1.5 MB")
    }

    func testLayoutJSONCarriesCharacters() {
        let j = OfficeWebLayout.vectorJSON(backgrounds: [:], catalog: [:])
        XCTAssertNotNil((j["characters"] as? [String: Any])?["atlas"])
    }
}
