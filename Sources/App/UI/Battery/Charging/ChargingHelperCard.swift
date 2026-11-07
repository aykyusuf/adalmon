import SwiftUI

/// Yardımcı kurulum durumu: Kur / Kaldır / Sistem Ayarları'nda onayla.
struct ChargingHelperCard: View {
    let model: ChargingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Yardımcı (AdalmonHelper)", systemImage: "lock.shield").font(.headline)
            HStack(spacing: 8) {
                Image(systemName: stateSymbol).foregroundStyle(stateTint)
                Text(model.installState.title)
                Spacer()
                actions
            }
            if model.installState == .requiresApproval {
                Text("Sistem Ayarları › Genel › Giriş Öğeleri ve Uzantılar bölümünde “Adalmon” için arka plan öğesini açın.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if model.installState.isEnabled, !model.reachable {
                Text("Yardımcı kurulu ama yanıt vermiyor; birkaç saniye bekleyin ya da yeniden kurun.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = model.errorText {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
        .batteryCard()
    }

    @ViewBuilder
    private var actions: some View {
        switch model.installState {
        case .notInstalled, .failed:
            Button("Kur", systemImage: "arrow.down.circle") { Task { await model.install() } }
        case .requiresApproval:
            Button("Sistem Ayarları'nı aç", systemImage: "gearshape") { model.openLoginItemsSettings() }
            Button("Kaldır", systemImage: "trash") { Task { await model.uninstall() } }
        case .enabled:
            Button("Kaldır", systemImage: "trash") { Task { await model.uninstall() } }
        case .notFound:
            EmptyView()
        }
    }

    private var stateSymbol: String {
        switch model.installState {
        case .enabled: "checkmark.circle.fill"
        case .requiresApproval: "hourglass.circle.fill"
        case .notInstalled: "circle.dashed"
        case .notFound, .failed: "xmark.octagon.fill"
        }
    }

    private var stateTint: Color {
        switch model.installState {
        case .enabled: .green
        case .requiresApproval: .orange
        case .notInstalled: .secondary
        case .notFound, .failed: .red
        }
    }
}
