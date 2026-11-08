import SpriteKit
import XCTest
@testable import Adalmon

/// Ofis v4: vektör tema (tema ayarı, kesirli kamera, doku üreticisi, ışık parametreleri, pişirme bütçesi, web sözleşmesi).
@MainActor
final class OfficeV4Tests: XCTestCase {
    private func assets() throws -> OfficeAssets { try XCTUnwrap(OfficeAssets.shared, "ofis varlıkları yüklenemedi") }

    private func members(_ n: Int, session id: String = "s") -> [OfficeMember] {
        [OfficeMember(id: id, parentID: nil, kind: .session, label: "oturum-\(id)", badge: .opus, status: .thinking, groupIndex: 0)]
            + (0..<n).map { OfficeMember(id: "\(id)#a\($0)", parentID: id, kind: .subagent, label: "scanner", badge: .haiku, status: .thinking, groupIndex: 0) }
    }

    // MARK: Tema ayarı

    func testThemePersistenceAndBadValueFallsBackToVector() {
        let d = UserDefaults(suiteName: "OfficeV4Tests.\(UUID().uuidString)")!
        XCTAssertEqual(OfficeTheme.stored(d), .vector, "varsayılan vektör")
        OfficeTheme.store(.pixel, defaults: d)
        XCTAssertEqual(OfficeTheme.stored(d), .pixel)
        OfficeTheme.store(.vector, defaults: d)
        XCTAssertEqual(OfficeTheme.stored(d), .vector)
        d.set("neon", forKey: OfficeTheme.defaultsKey)
        XCTAssertEqual(OfficeTheme.stored(d), .vector, "bozuk değer varsayılan")
        d.set(42, forKey: OfficeTheme.defaultsKey)
        XCTAssertEqual(OfficeTheme.stored(d), .vector)
        XCTAssertEqual(OfficeTheme.vector.textureScale, 4)
        XCTAssertFalse(OfficeTheme.vector.integerZoomOnly)
        XCTAssertTrue(OfficeTheme.pixel.integerZoomOnly)
    }

    // MARK: Kamera

    func testFractionalFitFillsViewWithMargin() {
        let view = CGSize(width: 1000, height: 640)
        let room = OfficeRoomArranger.arrange([OfficeRoomSize(id: "a", width: 160, height: 218)], columns: 1)
        let z = OfficeCamera.fitScale(view: view, content: room.contentSize)
        XCTAssertEqual(z, min(1000 / room.contentWidth, 640 / room.contentHeight), accuracy: 1e-9)
        XCTAssertNotEqual(z, z.rounded(), "kesirli")
        XCTAssertGreaterThan(z, Double(OfficeCamera.fitZoom(view: view, content: room.contentSize)), "tamsayıdan büyük: sahneyi doldurur")
        // kenar boşluğu: içerik (oda + 2*margin) pencereye sığar, en az margin*z kadar boşluk kalır
        XCTAssertLessThanOrEqual(room.contentWidth * z, view.width + 1e-6)
        XCTAssertLessThanOrEqual(room.contentHeight * z, view.height + 1e-6)
        XCTAssertGreaterThanOrEqual((room.contentHeight - 218) / 2 * z, OfficeRoomArranger.margin * z - 1e-6)
        XCTAssertEqual(OfficeCamera.fitScale(view: CGSize(width: 9000, height: 9000), content: CGSize(width: 50, height: 50)), 8, "en çok 8x")
        XCTAssertEqual(OfficeCamera.fitScale(view: CGSize(width: 100, height: 100), content: CGSize(width: 3000, height: 2000)), 1, "en az 1")
        let f = OfficeCamera.focusScale(on: CGRect(x: 10, y: 10, width: 160, height: 218), content: room.contentSize, view: view)
        XCTAssertEqual(f.zoom, OfficeCamera.fitScale(view: view, content: CGSize(width: 184, height: 242)), accuracy: 1e-9)
        // piksel yolu aynı
        XCTAssertEqual(OfficeCamera.fitZoom(view: view, content: room.contentSize), 2)
    }

    func testMultiRoomGridUnchanged() {
        let sizes = (0..<10).map { OfficeRoomSize(id: "r\($0)", width: 176, height: 250) }
        let arr = OfficeRoomArranger.best(sizes, viewWidth: 1500, viewHeight: 900)
        XCTAssertGreaterThanOrEqual(arr.zoom, 1)
        XCTAssertEqual(arr.cells.count, 10)
        XCTAssertGreaterThan(arr.columns, 1)
    }

    func testVectorSceneFillsViewAndPixelStaysInteger() throws {
        let a = try assets()
        let size = CGSize(width: 1000, height: 640)
        let vec = OfficeScene(assets: a, size: size, theme: .vector)
        vec.apply(members: members(3), animated: false)
        XCTAssertEqual(vec.zoom, CGFloat(OfficeCamera.fitScale(view: size, content: vec.arrangement.contentSize)), accuracy: 1e-9)
        XCTAssertNotEqual(vec.zoom, vec.zoom.rounded())
        XCTAssertLessThanOrEqual(vec.zoom, 8)
        let pix = OfficeScene(assets: a, size: size, theme: .pixel)
        pix.apply(members: members(3), animated: false)
        XCTAssertEqual(pix.zoom, pix.zoom.rounded(), "piksel temada tamsayı")
        // odaya yakınlaşma da kesirli ve ≤ 8
        vec.select(vec.roomIDs[0], animated: false)
        XCTAssertLessThanOrEqual(vec.zoom, 8)
        XCTAssertGreaterThan(vec.zoom, 2)
        // tema değişimi: oda/üyeler korunur
        let ids = vec.memberIDs, rooms = vec.roomIDs
        vec.setTheme(.pixel)
        XCTAssertEqual(vec.theme, .pixel)
        XCTAssertEqual(vec.memberIDs, ids)
        XCTAssertEqual(vec.roomIDs, rooms)
        XCTAssertEqual(vec.zoom, vec.zoom.rounded())
        vec.shutdown(); pix.shutdown()
    }

    // MARK: Doku üreticisi

    func testVectorTexturesExistForEveryCatalogIDWithCorrectSizeAndAlpha() throws {
        let a = try assets()
        XCTAssertEqual(OfficeVectorArt.furnitureIDs, Set(a.catalog.keys), "katalogdaki her kimlik için vektör karşılığı")
        for (id, asset) in a.catalog {
            let img = try XCTUnwrap(OfficeVectorArt.furniture(asset), "\(id) dokusu yok")
            XCTAssertEqual(img.width, asset.width * 4, id)
            XCTAssertEqual(img.height, asset.height * 4, id)
            XCTAssertTrue([.premultipliedLast, .premultipliedFirst, .last, .first].contains(img.alphaInfo), "\(id) alfa kanalı")
            XCTAssertNotNil(a.furnitureTexture(id, theme: .vector))
        }
        // alfa gerçekten kullanılıyor: masa köşesi saydam
        let desk = try XCTUnwrap(OfficeVectorArt.furniture(try XCTUnwrap(a.catalog["DESK_FRONT"])))
        XCTAssertEqual(try alphaAt(desk, 0, 0), 0)
        XCTAssertGreaterThan(try alphaAt(desk, desk.width / 2, desk.height / 3), 200)
        for pc in OfficeArt.allComputers {
            for frame in [nil, 0, 1, 2] as [Int?] {
                let name = OfficeArt.computerName(pc, frame: frame)
                let img = try XCTUnwrap(OfficeVectorArt.art(name), name)
                XCTAssertEqual(img.width, 64, name); XCTAssertEqual(img.height, 128, name)
            }
        }
        XCTAssertEqual(OfficeVectorArt.boardFrames().count, 3)
        XCTAssertEqual(OfficeVectorArt.door()?.width, 64)
        for g in OfficeVectorArt.glowSpecs { XCTAssertEqual(OfficeVectorArt.art(g.name)?.width, g.logicalW * 4) }
        XCTAssertEqual(a.furnitureTexture("DESK_FRONT", theme: .vector)?.filteringMode, .linear)
        XCTAssertEqual(a.furnitureTexture("DESK_FRONT", theme: .pixel)?.filteringMode, .nearest)
    }

    private func alphaAt(_ img: CGImage, _ x: Int, _ y: Int) throws -> UInt8 {
        let data = try XCTUnwrap(img.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!
        return ptr[y * img.bytesPerRow + x * 4 + 3]
    }

    // MARK: Işık

    func testLightingParametersRanges() {
        let v = OfficeTheme.vector.lighting, p = OfficeTheme.pixel.lighting
        XCTAssertTrue((0.18...0.22).contains(v.overlayAlpha))
        for a in [v.bulbAlpha, v.poolAlpha, v.boardAlpha] { XCTAssertTrue((0.30...0.40).contains(a), "\(a)") }
        XCTAssertTrue((0.1...0.4).contains(v.windowAlpha))
        XCTAssertEqual(p.overlayAlpha, OfficeLighting.nightOverlayAlpha, "piksel eski değerler")
        XCTAssertEqual(p.multiplyColor, [0.14, 0.18, 0.40])
        XCTAssertEqual(p.bulbAlpha, 0.85)
        // vektör gece örtüsü okunur: hiçbir kanal çarpanı 0.5'in altına inmez
        XCTAssertTrue(v.multiplyColor.allSatisfy { $0 >= 0.5 && $0 <= 1 })
        XCTAssertEqual(OfficeLighting.isNight(mode: .night, date: .now), true)
    }

    func testNightOverlayWashAndWindowsOnlyInVectorTheme() throws {
        let a = try assets()
        let vec = OfficeScene(assets: a, size: CGSize(width: 1000, height: 640), theme: .vector)
        vec.setLightingMode(.night, animated: false)
        vec.apply(members: members(3), animated: false)
        let day = OfficeScene(assets: a, size: CGSize(width: 1000, height: 640), theme: .vector)
        day.setLightingMode(.day, animated: false)
        day.apply(members: members(3), animated: false)
        XCTAssertGreaterThan(vec.nodeCount, day.nodeCount, "gece katmanı yalnızca geceyi ekler")
        vec.shutdown(); day.shutdown()
    }

    // MARK: Pişirilmiş oda bütçesi

    func testBakedRoomTextureSizeBudget() throws {
        let a = try assets()
        var total = 0
        for tier in OfficeRoomTier.allCases {
            let kit = a.kit(tier)
            let baked = try XCTUnwrap(OfficeVectorArt.bakeRoom(layout: kit.layout, catalog: a.catalog, bounds: kit.bounds))
            XCTAssertEqual(baked.image.width, kit.worldWidth * 4, tier.key)
            XCTAssertEqual(baked.image.height, kit.worldHeight * 4, tier.key)
            XCTAssertLessThanOrEqual(baked.image.width * baked.image.height * 4, kit.worldWidth * 64 * kit.worldHeight * 64 * 4)
            XCTAssertFalse(baked.windows.isEmpty, "pencere")
            total += baked.image.width * baked.image.height * 4
            _ = a.background(tier, theme: .vector)
        }
        XCTAssertLessThan(total, 200 * 1_048_576, "tüm kademeler toplam <200 MB")
        let again = a.vectorBackgroundBytes
        _ = a.background(.s16, theme: .vector)
        XCTAssertEqual(a.vectorBackgroundBytes, again, "tier başına bir kez pişirilir (paylaşılır)")
        print("V4 pisirme toplam=\(total / 1_048_576) MB")
    }

    // MARK: Web sözleşmesi

    func testWebLayoutCarriesVectorSection() throws {
        let root = try XCTUnwrap(OfficeAssets.bundleRoot())
        let built = try XCTUnwrap(OfficeWebLayout.build(officeRoot: root))
        print("V4 layout-json=\(built.json.count / 1024) KB")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: built.json) as? [String: Any])
        XCTAssertEqual(json["theme"] as? String, "vector")
        let v3 = try XCTUnwrap(json["v3"] as? [String: Any])
        let generated = try XCTUnwrap(v3["generated"] as? [String: String])
        XCTAssertNotNil(generated["imac_blue_on1"], "eski piksel anahtarları korunur")
        let vec = try XCTUnwrap(v3["vector"] as? [String: Any])
        XCTAssertEqual(vec["theme"] as? String, "vector")
        XCTAssertEqual(vec["scale"] as? Int, 4)
        let vg = try XCTUnwrap(vec["generated"] as? [String: String])
        for k in ["imac_blue_on1", "macbook_gray_off", "lamp"] { XCTAssertTrue(vg[k]?.hasPrefix("data:image/png;base64,") == true, k) }
        XCTAssertEqual((vec["furniture"] as? [String: String])?.count, OfficeVectorArt.furnitureIDs.count)
        XCTAssertEqual((vec["backgrounds"] as? [String: Any])?.count, 6)
        XCTAssertNotNil((json["furniture"] as? [String: Any])?["DESK_FRONT"], "mevcut furniture dosya eşlemesi bozulmadı")
    }
}
