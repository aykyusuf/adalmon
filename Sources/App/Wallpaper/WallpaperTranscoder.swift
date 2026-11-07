import AVFoundation
import Foundation

/// "Pil dostu dönüştür": AVAssetExportSession → HEVC 1080p (`AVAssetExportPresetHEVC1920x1080`), ses kaldırılmış.
/// Preset kare hızını düşürmez; kaynak hedefin üstündeyse `AVVideoComposition.frameDuration` ile hedef kare hızına indirilir.
private struct SessionBox: @unchecked Sendable { let session: AVAssetExportSession }

enum WallpaperTranscoder {
    enum TranscodeError: Error, LocalizedError {
        case noVideoTrack, sessionUnavailable, failed(String)
        var errorDescription: String? {
            switch self {
            case .noVideoTrack: "Dosyada video izi yok."
            case .sessionUnavailable: "Bu dosya için dönüştürme oturumu açılamadı."
            case .failed(let m): "Dönüştürme başarısız: \(m)"
            }
        }
    }

    static let targetBitsPerSecond = 5_000_000

    /// Hedef boyut: 1920x1080 içine sığacak şekilde (küçük videolar büyütülmez), çift sayılar.
    static func fitSize(width: Double, height: Double, maxWidth: Double = 1920, maxHeight: Double = 1080) -> (scale: Double, width: Int, height: Int) {
        let s = min(1, maxWidth / max(width, 1), maxHeight / max(height, 1))
        func even(_ v: Double) -> Int { max(2, Int((v / 2).rounded()) * 2) }
        return (s, even(width * s), even(height * s))
    }

    /// Kare hızı düşürülmeli mi?
    static func needsFrameRateReduction(source: Double, cap: WallpaperFrameRateCap) -> Bool {
        cap != .unlimited && source > Double(cap.rawValue) + 1
    }

    @discardableResult
    static func convert(source: URL, destination: URL, cap: WallpaperFrameRateCap,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw TranscodeError.noVideoTrack }
        let (size, fps, transform, range) = try await track.load(.naturalSize, .nominalFrameRate, .preferredTransform, .timeRange)

        // Yalnızca video izini taşıyan kompozisyon: ses izi kopyalanmaz.
        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw TranscodeError.sessionUnavailable }
        try compTrack.insertTimeRange(range, of: track, at: .zero)
        compTrack.preferredTransform = transform

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHEVC1920x1080) else { throw TranscodeError.sessionUnavailable }
        // Preset bit hızını kendisi seçer (240 fps kaynakta ~57 Mb/sn gözlendi); en iyi çabayla ~5 Mb/sn üst sınır.
        let seconds = range.duration.seconds
        if seconds.isFinite, seconds > 0 { session.fileLengthLimit = Int64(seconds * Double(targetBitsPerSecond) / 8) }
        if needsFrameRateReduction(source: Double(fps), cap: cap) {
            let oriented = size.applying(transform)
            let fit = fitSize(width: abs(oriented.width), height: abs(oriented.height))
            let video = AVMutableVideoComposition()
            video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(cap.rawValue))
            video.renderSize = CGSize(width: fit.width, height: fit.height)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
            layer.setTransform(transform.concatenating(CGAffineTransform(scaleX: fit.scale, y: fit.scale)), at: .zero)
            instruction.layerInstructions = [layer]
            video.instructions = [instruction]
            session.videoComposition = video
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Oturum, Apple'ın tasarımı gereği hem dışa aktarma hem durum akışı için eşzamanlı kullanılır.
        let box = SessionBox(session: session)
        let exporter = Task { try await box.session.export(to: destination, as: .mov) }
        do {
            try await withTaskCancellationHandler {
                for await state in session.states(updateInterval: 0.25) {
                    if case .exporting(let p) = state { progress(p.fractionCompleted) }
                }
                try await exporter.value
            } onCancel: { exporter.cancel() }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw TranscodeError.failed(error.localizedDescription)
        }
        progress(1)
        return destination
    }
}
