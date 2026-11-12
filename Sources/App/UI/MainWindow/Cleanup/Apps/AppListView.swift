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

/// Kurulu uygulamalar: her biri bir kart (simge, ad, boyut, artık). Seçilen kart açılır ve artıklarını gösterir;
/// aynı anda tek uygulama seçilebilir. Kaydırma üstteki sayfa tarafından yapılır.
struct AppListView: View {
    @Bindable var model: UninstallerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let accent = CleanupAccent.uninstaller

    var body: some View {
        let apps = model.visibleApps
        LazyVStack(spacing: 8) {
            ForEach(apps) { app in
                AppCard(app: app, model: model, accent: accent)
            }
            if apps.isEmpty { ContentUnavailableView.search(text: model.search) }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.05), value: model.selectedAppID)
    }
}

private struct AppCard: View {
    let app: InstalledApp
    @Bindable var model: UninstallerModel
    let accent: CleanupAccent
    @State private var hovered = false

    private var isSelected: Bool { model.selectedAppID == app.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isSelected {
                AppLeftoverDetail(model: model, app: app)
                    .padding(.horizontal, 14).padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
        .background(Color.primary.opacity(hovered ? 0.08 : 0.05), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(isSelected ? accent.base.opacity(0.55) : Color.clear, lineWidth: 1.5))
        .onHover { hovered = $0 }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIconView(path: app.path, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).font(.body.weight(.medium)).lineLimit(1)
                    if model.isRunning(app) { badge("Açık", .orange) }
                    if app.isAppStore { badge("App Store", .blue) } else if app.ownerIsRoot { badge("Yönetici", .gray) }
                }
                Text([app.version.map { "Sürüm \($0)" }, app.bundleID].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.bytes(app.bytes)).font(.callout.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                if app.leftoverBytes > 0 {
                    Text("+ \(Format.bytes(app.leftoverBytes)) artık").font(.caption).foregroundStyle(accent.base).monospacedDigit()
                }
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isSelected ? 90 : 0)).frame(width: 14)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(.rect)
        .onTapGesture { model.select(isSelected ? nil : app) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isSelected ? "Artıkları gizle" : "Artıkları göster")
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.14), in: .capsule)
    }
}
