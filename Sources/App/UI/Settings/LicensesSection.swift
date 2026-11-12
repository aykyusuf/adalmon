import SwiftUI

/// Ayarlar › Genel › Lisanslar.
struct LicensesSection: View {
    var body: some View {
        Section("Lisanslar") {
            ForEach(ThirdPartyNotice.all) { notice in
                LabeledContent {
                    Link(notice.license, destination: notice.url)
                } label: {
                    Text(notice.name)
                    Text("sürüm \(notice.version)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(ThirdPartyNotice.lgplStatement).font(.caption).foregroundStyle(.secondary)
            Text(ThirdPartyNotice.trademarkStatement).font(.caption).foregroundStyle(.secondary)
        }
    }
}
