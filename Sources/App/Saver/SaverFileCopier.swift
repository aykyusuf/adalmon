import Darwin
import Foundation

/// Video kopyası: önce `clonefile` (APFS, aynı birim: anında, ek disk alanı YOK), olmazsa ilerlemeli akış kopyası.
enum SaverFileCopier {
    enum Method: Equatable, Sendable { case clone, stream }

    /// `destination` yoksa oluşturur; yarım dosya bırakmaz (geçici ada yazıp taşır). `progress` 0...1.
    @discardableResult
    static func copy(from source: URL, to destination: URL, chunkSize: Int = 8 << 20, allowClone: Bool = true,
                     progress: @Sendable (Double) -> Void = { _ in }) throws -> Method {
        let fm = FileManager.default
        let temp = destination.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).part")
        defer { try? fm.removeItem(at: temp) }
        if allowClone, clonefile(source.path, temp.path, 0) == 0 {
            try replace(destination, with: temp)
            progress(1)
            return .clone
        }
        let total = max(1, Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        guard fm.createFile(atPath: temp.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: temp)
        defer { try? input.close(); try? output.close() }
        var done: Int64 = 0
        while true {
            try Task.checkCancellation()
            let data = try autoreleasepool { try input.read(upToCount: chunkSize) }
            guard let data, !data.isEmpty else { break }
            try output.write(contentsOf: data)
            done += Int64(data.count)
            progress(min(1, Double(done) / Double(total)))
        }
        try output.synchronize()
        try replace(destination, with: temp)
        progress(1)
        return .stream
    }

    private static func replace(_ destination: URL, with temp: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: temp, to: destination)
    }
}
