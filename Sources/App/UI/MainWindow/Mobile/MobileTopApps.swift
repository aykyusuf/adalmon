import SwiftUI

/// Bugün mobil veriyi en çok kullanan uygulamalar.
struct MobileTopApps: View {
    let apps: [AppUsage]

    var body: some View {
        MobileCard("Mobil veriyi en çok kullananlar", systemImage: "list.number") {
            if apps.isEmpty {
                Text("Bugün mobil veride uygulama trafiği yok.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                let peak = Double(apps.first?.mobileBytes ?? 1)
                VStack(spacing: 10) {
                    ForEach(apps) { usage in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(nsImage: AppCatalog.shared.icon(for: usage.app))
                                    .resizable()
                                    .frame(width: 22, height: 22)
                                    .accessibilityHidden(true)
                                Text(AppCatalog.shared.name(for: usage.app)).lineLimit(1)
                                Spacer()
                                Text(Format.bytes(usage.mobileBytes))
                                    .font(.callout)
                                    .monospacedDigit()
                                    .foregroundStyle(.orange)
                            }
                            UsageBar(fraction: Double(usage.mobileBytes) / peak, tint: .orange.opacity(0.7), height: 4)
                                .padding(.leading, 30)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}
