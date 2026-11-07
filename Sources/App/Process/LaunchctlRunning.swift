import Foundation

/// `launchctl` çalıştırıcısı; testlerde sahtesi kullanılır (gerçek ajanlar asla değiştirilmez).
protocol LaunchctlRunning: Sendable {
    func run(_ command: LaunchctlCommand) async -> CommandResult
}

struct SystemLaunchctl: LaunchctlRunning {
    func run(_ command: LaunchctlCommand) async -> CommandResult {
        await CommandRunner.run("/bin/launchctl", command.arguments, timeout: 15)
    }
}
