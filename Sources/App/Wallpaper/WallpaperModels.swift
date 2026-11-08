import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

enum WallpaperKind: String, Codable, Sendable {
    case video, image

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]
    static var allExtensions: [String] { Array(videoExtensions.union(imageExtensions)).sorted() }

    init?(url: URL) {
        let ext = url.pathExtension.lowercased()
        if Self.videoExtensions.contains(ext) { self = .video }
        else if Self.imageExtensions.contains(ext) { self = .image }
        else { return nil }
    }
}

/// Dosyadan okunan teknik bilgi.
struct WallpaperMediaInfo: Codable, Equatable, Sendable {
    var width: Int
    var height: Int
    var frameRate: Double
    /// "HEVC", "H.264", "ProRes"… (görüntülerde "Görüntü").
    var codec: String
    var hasAudio: Bool
    var duration: Double

    /// "1080p HEVC" gibi kısa etiket.
    var qualityText: String {
        let longSide = max(width, height), shortSide = min(width, height)
        let label: String
        switch shortSide {
        // 4K: 3840x2160 ve sinematik kırpmalar (3840x1600 gibi, uzun kenar >= 3800) da 4K sayılır.
        case _ where shortSide >= 2160 || longSide >= 3800: label = "4K"
        case 1440...: label = "1440p"
        case 1000...: label = "1080p"
        case 700...: label = "720p"
        default: label = "\(shortSide)p"
        }
        return "\(label) \(codec)"
    }
}

/// Kütüphanedeki bir içerik. Dosya yerinde referanslanır (kopyalanmaz: disk); "Pil dostu dönüştür" kopyayı
/// `~/Library/Application Support/Adalmon/Wallpapers/` altına yazar.
struct WallpaperItem: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var path: String
    var kind: WallpaperKind
    var addedAt: Date
    var byteSize: Int64
    var info: WallpaperMediaInfo?
    /// Dönüştürülmüş kopyaysa özgün dosyanın boyutu ("önce / sonra").
    var originalByteSize: Int64?
    var isOptimized: Bool = false

    var url: URL { URL(filePath: path) }
    var fileExists: Bool { FileManager.default.fileExists(atPath: path) }
}

/// "Tahmini enerji" etiketi: ölçüm değil, kaba sınıflama (bkz. docs: tek koşu probe ~%1,1-1,3 CPU @1080p30 HEVC).
enum WallpaperEnergyEstimate: String, Sendable {
    case none, low, medium, high

    var text: String {
        switch self {
        case .none: "enerji yok"
        case .low: "tahmini enerji düşük"
        case .medium: "tahmini enerji orta"
        case .high: "tahmini enerji yüksek"
        }
    }

    static func estimate(kind: WallpaperKind, info: WallpaperMediaInfo?) -> Self {
        guard kind == .video, let info else { return .none }
        let pixels = info.width * info.height
        let hevc = info.codec == "HEVC"
        let fps = info.frameRate
        if pixels > 2_800_000 * 2 || fps > 45 && pixels > 2_800_000 { return .high }   // 4K ya da 4K60
        if pixels <= 2_100_000 + 100_000 && fps <= 31 && hevc { return .low }          // ≤1080p30 HEVC
        return .medium
    }
}

/// Kare hızı sınırı. Oynatma sırasında uygulanmaz (AVPlayerItem'ın yerel dosyada fps sınırı yoktur;
/// `preferredPeakBitRate` / `preferredMaximumResolution` yalnızca HLS'te etkilidir, videoComposition ise GPU birleştirme maliyeti ekler).
/// Sınır "Pil dostu dönüştür" adımında uygulanır.
enum WallpaperFrameRateCap: Int, Codable, CaseIterable, Identifiable, Sendable {
    case unlimited = 0, fps30 = 30, fps24 = 24
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .unlimited: "Sınırsız"
        case .fps30: "30 kare/sn (önerilen)"
        case .fps24: "24 kare/sn"
        }
    }
}

struct WallpaperSettings: Codable, Equatable, Sendable {
    /// Ana şalter. Kapalıyken hiçbir pencere, zamanlayıcı ya da gözlemci yoktur.
    var enabled = false
    var rules = WallpaperPauseRules()
    var sameOnAllScreens = true
    var defaultItemID: UUID?
    var perScreen: [String: UUID] = [:]
    var playlistMode: PlaylistMode = .single
    var rotationMinutes = 30
    var frameRateCap: WallpaperFrameRateCap = .fps30
    /// Döngü: baştan atla / sondan kes / çapraz geçiş. Ekran koruyucu da aynı değerleri kullanır.
    var loop = LoopSettings()
    /// Deneysel B bölümü gösterilsin mi (kapalı gelir).
    var experimentalAerialAcknowledged = false
    /// Kilit ekranında / Sistem Ayarları'nda da göster (deneysel): açıkken geçerli duvar kâğıdı videosu Aerial listesine kaydedilir.
    var showInSystem = false
    /// İçerik kaynağı: video kütüphanesi ya da canlı ajan ofisi (aynı anda yalnızca biri). Eski kayıtlarda yok → video.
    var source: WallpaperSource = .video
    /// Ofis kaynağının seçenekleri (ışık, arka plan, etiketler).
    var office = OfficeWallpaperOptions()

    static let rotationChoices = [5, 15, 30, 60, 180, 1_440]
}

extension WallpaperSettings {
    /// Eski kayıtlarda olmayan anahtarlar varsayılana düşer: yeni alan eklemek kayıtlı ayarları SİLMEZ.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WallpaperSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        rules = try c.decodeIfPresent(WallpaperPauseRules.self, forKey: .rules) ?? d.rules
        sameOnAllScreens = try c.decodeIfPresent(Bool.self, forKey: .sameOnAllScreens) ?? d.sameOnAllScreens
        defaultItemID = try c.decodeIfPresent(UUID.self, forKey: .defaultItemID)
        perScreen = try c.decodeIfPresent([String: UUID].self, forKey: .perScreen) ?? d.perScreen
        playlistMode = try c.decodeIfPresent(PlaylistMode.self, forKey: .playlistMode) ?? d.playlistMode
        rotationMinutes = try c.decodeIfPresent(Int.self, forKey: .rotationMinutes) ?? d.rotationMinutes
        frameRateCap = try c.decodeIfPresent(WallpaperFrameRateCap.self, forKey: .frameRateCap) ?? d.frameRateCap
        loop = (try? c.decodeIfPresent(LoopSettings.self, forKey: .loop)) ?? d.loop
        experimentalAerialAcknowledged = try c.decodeIfPresent(Bool.self, forKey: .experimentalAerialAcknowledged) ?? d.experimentalAerialAcknowledged
        showInSystem = try c.decodeIfPresent(Bool.self, forKey: .showInSystem) ?? d.showInSystem
        source = (try? c.decodeIfPresent(WallpaperSource.self, forKey: .source)) ?? d.source   // bozuk değer → video
        office = (try? c.decodeIfPresent(OfficeWallpaperOptions.self, forKey: .office)) ?? d.office
    }
}

// MARK: Dosya incelemesi

enum WallpaperMedia {
    static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    static func probe(_ url: URL, kind: WallpaperKind) async -> WallpaperMediaInfo? {
        switch kind {
        case .image:
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
            return WallpaperMediaInfo(width: w, height: h, frameRate: 0, codec: "Görüntü", hasAudio: false, duration: 0)
        case .video:
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let (size, fps, transform, formats) = try? await track.load(.naturalSize, .nominalFrameRate, .preferredTransform, .formatDescriptions) else { return nil }
            let oriented = size.applying(transform)
            let audio = ((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty == false
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            return WallpaperMediaInfo(width: Int(abs(oriented.width)), height: Int(abs(oriented.height)), frameRate: Double(fps),
                                      codec: codecName(formats.first.map { CMFormatDescriptionGetMediaSubType($0) }), hasAudio: audio,
                                      duration: duration.isFinite ? duration : 0)
        }
    }

    static func codecName(_ subtype: FourCharCode?) -> String {
        guard let subtype else { return "?" }
        switch subtype {
        case kCMVideoCodecType_HEVC: return "HEVC"
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes4444, kCMVideoCodecType_AppleProRes422HQ,
             kCMVideoCodecType_AppleProRes422LT, kCMVideoCodecType_AppleProRes422Proxy: return "ProRes"
        case kCMVideoCodecType_VP9: return "VP9"
        default:
            let bytes = [UInt8((subtype >> 24) & 0xFF), UInt8((subtype >> 16) & 0xFF), UInt8((subtype >> 8) & 0xFF), UInt8(subtype & 0xFF)]
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    /// Oynatma için üst sınır: ekran piksel boyutu (görüntüler bu boyuta indirilerek yüklenir: bellek).
    static func downsampledImage(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Videodan (ya da görüntüden) bir kare: küçük resim ve duraklatılmış poster için.
    /// `loop`: verilirse ve video kırpılıyorsa kare tam kırpma başlangıcından alınır (soğuk açılışta poster = ilk oynayan kare).
    static func frameImage(_ url: URL, kind: WallpaperKind, maxPixel: Int, at seconds: Double = 1, loop: LoopTiming? = nil) async -> CGImage? {
        switch kind {
        case .image: return downsampledImage(url, maxPixel: maxPixel)
        case .video:
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
            // Videoların başı çoğu zaman siyah ya da kararmayla açılır: kareyi sürenin ~%15'inden (en az 3 sn, en çok 60 sn) al.
            let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            var smart = duration.isFinite && duration > 0 ? min(60, max(3, duration * 0.15)) : seconds
            if let loop {
                let range = loop.range(duration: duration)
                if range.isTrimmed { smart = range.start }
            }
            for t in [min(smart, max(0, duration - 0.5)), seconds, 0] {
                if let image = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image { return image }
            }
            return nil
        }
    }

    static func jpegData(_ image: CGImage, quality: CGFloat = 0.8) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
