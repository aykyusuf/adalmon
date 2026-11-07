import Foundation

/// Bir komut çalıştırmanın sonucu (çıkış kodu + stdout/stderr birleşik çıktı).
struct CommandResult: Sendable, Equatable {
    var status: Int32
    var output: String
    var succeeded: Bool { status == 0 }
}

/// Dış bir programı (kabuk olmadan, argüman dizisiyle) ana iş parçacığı dışında çalıştırır.
enum CommandRunner {
    /// `timeout` sonunda süreç sonlandırılır; çıktı o ana kadar okunanla döner.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 20) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runBlocking(executable, arguments, timeout: timeout))
            }
        }
    }

    private static func runBlocking(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch {
            return CommandResult(status: -1, output: error.localizedDescription)
        }
        nonisolated(unsafe) let running = process
        let killer = DispatchWorkItem { if running.isRunning { running.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
