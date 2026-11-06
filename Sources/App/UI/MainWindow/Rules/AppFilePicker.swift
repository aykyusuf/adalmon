import AppKit
import UniformTypeIdentifiers

/// Listede olmayan bir uygulamayı dosya seçiciyle (.app) seçtirir.
enum AppFilePicker {
    @MainActor
    static func pick() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Uygulama seç"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(filePath: "/Applications")
        return panel.runModal() == .OK ? panel.url?.standardizedFileURL.path : nil
    }
}
