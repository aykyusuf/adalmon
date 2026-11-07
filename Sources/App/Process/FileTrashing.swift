import AppKit
import Foundation

/// Dosyayı Çöp Kutusu'na taşır; testlerde sahtesi kullanılır.
protocol FileTrashing: Sendable {
    func trash(_ url: URL) async throws
}

struct WorkspaceTrasher: FileTrashing {
    func trash(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            Task { @MainActor in
                NSWorkspace.shared.recycle([url]) { _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }
    }
}
