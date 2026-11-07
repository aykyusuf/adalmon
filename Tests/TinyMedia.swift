import AVFoundation
import CoreGraphics
import Foundation
import VideoToolbox
@testable import Adalmon

/// Testler için minik sentetik medya (birkaç KB). Çağıran silmekten sorumludur (geçici dizinde üretilir).
enum TinyMedia {
    static func video(at url: URL, width: Int = 128, height: Int = 72, fps: Int32 = 30, frames: Int = 12, hue: CGFloat = 0.55) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pb = try XCTUnwrapBuffer(buffer)
            CVPixelBufferLockBaseAddress(pb, [])
            let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pb)
            for y in 0..<height { for x in 0..<width {
                let o = y * stride + x * 4
                base[o] = UInt8((x * 255 / width + i * 8) % 256)
                base[o + 1] = UInt8((y * 255 / height) % 256)
                base[o + 2] = UInt8(hue * 255)
                base[o + 3] = 255
            } }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    private static func XCTUnwrapBuffer(_ b: CVPixelBuffer?) throws -> CVPixelBuffer {
        guard let b else { throw CocoaError(.fileWriteUnknown) }
        return b
    }

    static func png(at url: URL, width: Int = 320, height: Int = 200, hue: CGFloat = 0.1) throws {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red: hue, green: 0.4, blue: 0.9, alpha: 1), CGColor(red: 0.9, green: hue, blue: 0.3, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        guard let data = WallpaperMedia.pngData(ctx.makeImage()!) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }
}
