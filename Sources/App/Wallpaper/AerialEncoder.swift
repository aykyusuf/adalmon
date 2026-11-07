import AVFoundation
import CoreMedia
import VideoToolbox

/// Seçenek B için kodlayıcı: QuickTime .mov, HEVC Main10 (hvc1), ses YOK, ilk PTS = 0, sıralı katmanlı (temporal) kodlama
/// (`BaseLayerFrameRate = fps/2` → en az 2 temporal katman istenir). ExportSession temporal katman veremez; AVAssetWriter şart.
enum AerialEncoder {
    enum EncodeError: Error, LocalizedError {
        case noVideoTrack, readerFailed(String), writerFailed(String)
        var errorDescription: String? {
            switch self {
            case .noVideoTrack: "Dosyada video izi yok."
            case .readerFailed(let m): "Okuma hatası: \(m)"
            case .writerFailed(let m): "Yazma hatası: \(m)"
            }
        }
    }

    static func bitrate(width: Int, height: Int, fps: Double) -> Int {
        min(40_000_000, max(2_000_000, Int(Double(width * height) * fps * 0.07)))
    }

    static func compressionProperties(width: Int, height: Int, fps: Double) -> [String: Any] {
        [AVVideoAverageBitRateKey: bitrate(width: width, height: height, fps: fps),
         AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
         AVVideoExpectedSourceFrameRateKey: fps,
         AVVideoMaxKeyFrameIntervalKey: max(1, Int(fps.rounded()) * 2),
         AVVideoAllowFrameReorderingKey: false,
         kVTCompressionPropertyKey_BaseLayerFrameRate as String: max(1, fps / 2)]
    }

    /// `source` → `videoDestination` (.mov) + `thumbnailDestination` (.png).
    static func encode(source: URL, videoDestination: URL, thumbnailDestination: URL,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        try await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: source)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw EncodeError.noVideoTrack }
            let (size, nominal, transform) = try await track.load(.naturalSize, .nominalFrameRate, .preferredTransform)
            let total = try await asset.load(.duration).seconds
            let fps = nominal > 1 ? Double(nominal) : 30
            let width = Int(size.width), height = Int(size.height)
            try? FileManager.default.removeItem(at: videoDestination)
            try FileManager.default.createDirectory(at: videoDestination.deletingLastPathComponent(), withIntermediateDirectories: true)

            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            ])
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw EncodeError.readerFailed("çıkış eklenemedi") }
            reader.add(output)

            let writer = try AVAssetWriter(outputURL: videoDestination, fileType: .mov)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: width, AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compressionProperties(width: width, height: height, fps: fps),
            ]
            // Desteklenmeyen özellik AVAssetWriterInput'ta Objective-C istisnası (çökme) üretir: önce doğrula.
            guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
                throw EncodeError.writerFailed("Bu macOS sürümü istenen HEVC Main10 / katmanlı kodlama ayarlarını kabul etmiyor.")
            }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            input.transform = transform
            guard writer.canAdd(input) else { throw EncodeError.writerFailed("giriş eklenemedi") }
            writer.add(input)

            guard reader.startReading() else { throw EncodeError.readerFailed(reader.error?.localizedDescription ?? "başlatılamadı") }
            guard writer.startWriting() else { throw EncodeError.writerFailed(writer.error?.localizedDescription ?? "başlatılamadı") }
            writer.startSession(atSourceTime: .zero)

            var firstPTS: CMTime?
            while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                let base = firstPTS ?? pts
                firstPTS = base
                var timing = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(sample), presentationTimeStamp: CMTimeSubtract(pts, base), decodeTimeStamp: .invalid)
                var shifted: CMSampleBuffer?
                CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &shifted)
                while !input.isReadyForMoreMediaData {
                    if writer.status == .failed { throw EncodeError.writerFailed(writer.error?.localizedDescription ?? "?") }
                    try await Task.sleep(for: .milliseconds(2))
                }
                guard let shifted, input.append(shifted) else { throw EncodeError.writerFailed(writer.error?.localizedDescription ?? "kare eklenemedi") }
                if total > 0 { progress(min(0.99, CMTimeSubtract(pts, base).seconds / total)) }
            }
            if reader.status == .failed { throw EncodeError.readerFailed(reader.error?.localizedDescription ?? "?") }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw EncodeError.writerFailed(writer.error?.localizedDescription ?? "tamamlanamadı") }

            guard let image = await WallpaperMedia.frameImage(source, kind: .video, maxPixel: 1280, at: 1), let png = WallpaperMedia.pngData(image) else {
                throw EncodeError.writerFailed("küçük resim üretilemedi")
            }
            try png.write(to: thumbnailDestination, options: .atomic)
            progress(1)
        }.value
    }
}
