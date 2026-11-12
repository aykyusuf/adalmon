import SwiftUI

/// Erişim yardımı: nedeni, üç adımı, ayar düğmesini ve "Tekrar dene"yi gösterir.
/// Engel ayarlardan dönüldükten sonra da sürüyorsa "Adalmon'u yeniden başlat" önerilir.
struct AccessHelpSheet: View {
    let reason: AccessReason
    let monitor: CleanupAccessMonitor
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(reason.title, systemImage: reason == .systemProtected ? "lock.shield" : "lock")
                .font(.headline)
            Text(reason.explanation).fixedSize(horizontal: false, vertical: true)
            if !reason.steps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(reason.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)").font(.callout.bold()).monospacedDigit()
                                .frame(width: 20, height: 20)
                                .background(Color.accentColor.opacity(0.15), in: .circle)
                            Text(step).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if monitor.suggestRestart {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle").foregroundStyle(.orange)
                    Text("İzin verildiği hâlde erişim yoksa macOS değişikliği ancak yeniden açılışta uygular.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Adalmon'u yeniden başlat") { CleanupAccessMonitor.relaunch() }
                }
                .padding(10)
                .background(Color.orange.opacity(0.10), in: .rect(cornerRadius: 8))
            }
            HStack {
                if let button = reason.buttonTitle {
                    Button(button) { monitor.openSettings(for: reason) }
                        .buttonStyle(.borderedProminent)
                }
                Button("Tekrar dene") { monitor.reprobe() }
                Spacer()
                Button("Kapat") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

extension AccessReason: Identifiable {
    var id: Self { self }
}
