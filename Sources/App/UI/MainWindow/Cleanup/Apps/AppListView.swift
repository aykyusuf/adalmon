import AppKit
import SwiftUI

/// Uygulama simgesi: yalnızca satır ekrana gelince `NSWorkspace.icon(forFile:)` ile yüklenir (tembel).
struct AppIconView: View {
    let path: String
    var size: CGFloat = 32
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: path) { icon = NSWorkspace.shared.icon(forFile: path) }
    }
}

/// Sol bölme: kurulu uygulamalar (ad, sürüm, boyut, artık toplamı).
struct AppListView: View {
    @Bindable var model: UninstallerModel

    var body: some View {
        let apps = model.visibleApps
        List(selection: Binding(get: { model.selectedAppID }, set: { id in model.select(model.apps.first { $0.id == id }) })) {
            ForEach(apps) { app in
                AppRow(app: app, running: model.isRunning(app)).tag(app.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if apps.isEmpty { ContentUnavailableView.search(text: model.search) }
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let running: Bool

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(path: app.path)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).lineLimit(1)
                    if running { badge("Açık", .orange) }
                    if app.isAppStore { badge("App Store", .blue) } else if app.ownerIsRoot { badge("Yönetici", .gray) }
                }
                Text([app.version.map { "Sürüm \($0)" }, app.bundleID].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.bytes(app.bytes)).monospacedDigit()
                if app.leftoverBytes > 0 {
                    Text("Artık: \(Format.bytes(app.leftoverBytes))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.14), in: .capsule)
    }
}
