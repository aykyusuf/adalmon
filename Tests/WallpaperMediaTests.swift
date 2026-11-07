import AVFoundation
import XCTest
@testable import Adalmon

/// Dönüştürme (ExportSession), Aerial kodlayıcı (AVAssetWriter) ve medya incelemesi: minik sentetik klipler, test sonunda silinir.
final class WallpaperMediaTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "wp-media-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testFitSizeAndFrameRateRules() {
        let big = WallpaperTranscoder.fitSize(width: 3840, height: 2160)
        XCTAssertEqual(big.width, 1920); XCTAssertEqual(big.height, 1080)
        let small = WallpaperTranscoder.fitSize(width: 129, height: 73)
        XCTAssertEqual(small.scale, 1, "küçük videolar büyütülmez")
        XCTAssertEqual(small.width % 2, 0)
        let portrait = WallpaperTranscoder.fitSize(width: 1080, height: 1920)
        XCTAssertEqual(portrait.height, 1080)
        XCTAssertTrue(WallpaperTranscoder.needsFrameRateReduction(source: 60, cap: .fps30))
        XCTAssertFalse(WallpaperTranscoder.needsFrameRateReduction(source: 30, cap: .fps30))
        XCTAssertFalse(WallpaperTranscoder.needsFrameRateReduction(source: 120, cap: .unlimited))
    }

    func testEnergyEstimate() {
        func info(_ w: Int, _ h: Int, _ fps: Double, _ codec: String = "HEVC") -> WallpaperMediaInfo {
            .init(width: w, height: h, frameRate: fps, codec: codec, hasAudio: false, duration: 10)
        }
        XCTAssertEqual(WallpaperEnergyEstimate.estimate(kind: .video, info: info(1920, 1080, 30)), .low)
        XCTAssertEqual(WallpaperEnergyEstimate.estimate(kind: .video, info: info(1920, 1080, 60)), .medium)
        XCTAssertEqual(WallpaperEnergyEstimate.estimate(kind: .video, info: info(1920, 1080, 30, "H.264")), .medium)
        XCTAssertEqual(WallpaperEnergyEstimate.estimate(kind: .video, info: info(3840, 2160, 30)), .high)
        XCTAssertEqual(WallpaperEnergyEstimate.estimate(kind: .image, info: nil), .none)
        XCTAssertEqual(info(1920, 1080, 30).qualityText, "1080p HEVC")
    }

    func testProbeReadsVideoAndImage() async throws {
        let v = tmp.appending(path: "a.mov"); try await TinyMedia.video(at: v, width: 128, height: 72, fps: 30, frames: 6)
        let infoOpt = await WallpaperMedia.probe(v, kind: .video)
        let info = try XCTUnwrap(infoOpt)
        XCTAssertEqual(info.width, 128); XCTAssertEqual(info.height, 72)
        XCTAssertEqual(info.codec, "H.264"); XCTAssertFalse(info.hasAudio)
        let p = tmp.appending(path: "a.png"); try TinyMedia.png(at: p)
        let imgOpt = await WallpaperMedia.probe(p, kind: .image)
        let img = try XCTUnwrap(imgOpt)
        XCTAssertEqual(img.width, 320)
        let frame = await WallpaperMedia.frameImage(v, kind: .video, maxPixel: 64)
        XCTAssertNotNil(frame)
    }

    func testConvertReducesFrameRateToHEVCWithoutAudio() async throws {
        let src = tmp.appending(path: "src60.mov"); try await TinyMedia.video(at: src, width: 128, height: 72, fps: 60, frames: 60)
        let dst = tmp.appending(path: "out.mov")
        try await WallpaperTranscoder.convert(source: src, destination: dst, cap: .fps30) { _ in }
        let infoOpt = await WallpaperMedia.probe(dst, kind: .video)
        let info = try XCTUnwrap(infoOpt)
        print("ADALMON_CONVERT: \(info.width)x\(info.height) \(info.frameRate) fps \(info.codec) audio=\(info.hasAudio) \(WallpaperMedia.fileSize(src)) -> \(WallpaperMedia.fileSize(dst)) bytes")
        XCTAssertEqual(info.codec, "HEVC")
        XCTAssertFalse(info.hasAudio)
        XCTAssertLessThanOrEqual(info.frameRate, 31, "60 fps kaynak 30 fps'e inmeli")
        XCTAssertGreaterThan(info.frameRate, 20)
    }

    func testConvertWithoutReductionKeepsFrameRate() async throws {
        let src = tmp.appending(path: "src30.mov"); try await TinyMedia.video(at: src, frames: 30)
        let dst = tmp.appending(path: "out30.mov")
        try await WallpaperTranscoder.convert(source: src, destination: dst, cap: .fps30) { _ in }
        let infoOpt = await WallpaperMedia.probe(dst, kind: .video)
        let info = try XCTUnwrap(infoOpt)
        XCTAssertEqual(info.codec, "HEVC")
        XCTAssertEqual(info.frameRate, 30, accuracy: 1)
    }

    func testAerialEncoderProducesMain10HVC1WithoutAudioStartingAtZero() async throws {
        let src = tmp.appending(path: "src.mov"); try await TinyMedia.video(at: src, width: 256, height: 144, fps: 30, frames: 40)
        let out = tmp.appending(path: "aerial.mov"), thumb = tmp.appending(path: "aerial.png")
        try await AerialEncoder.encode(source: src, videoDestination: out, thumbnailDestination: thumb) { _ in }
        let asset = AVURLAsset(url: out)
        let trackOpt = try await asset.loadTracks(withMediaType: .video).first
        let track = try XCTUnwrap(trackOpt)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audio.isEmpty)
        let fdOpt = try await track.load(.formatDescriptions).first
        let fd = try XCTUnwrap(fdOpt)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(fd), kCMVideoCodecType_HEVC)
        XCTAssertEqual(fourCC(CMFormatDescriptionGetMediaSubType(fd)), "hvc1")
        let range = try await track.load(.timeRange)
        XCTAssertEqual(range.start.seconds, 0, accuracy: 0.0001)
        // hvcC: profile_idc (2 = Main10) ve temporal katman sayısı.
        let atoms = CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any]
        let hvcC = try XCTUnwrap(atoms?["hvcC"] as? Data)
        let profile = Int(hvcC[1] & 0x1F)
        let temporalLayers = Int((hvcC[21] >> 3) & 0x7)
        print("ADALMON_AERIAL: hvcC profile_idc=\(profile) numTemporalLayers=\(temporalLayers) bytes=\(WallpaperMedia.fileSize(out))")
        XCTAssertEqual(profile, 2, "HEVC Main10 olmalı")
        // Temporal katman sayısı kodlayıcı ve ortama bağlıdır; rapor için yazdırılır, burada yalnızca >= 1 doğrulanır.
        XCTAssertGreaterThanOrEqual(temporalLayers, 1)
        XCTAssertGreaterThan(WallpaperMedia.fileSize(thumb), 0)
    }

    private func fourCC(_ v: FourCharCode) -> String {
        String(decoding: [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)], as: UTF8.self)
    }
}
