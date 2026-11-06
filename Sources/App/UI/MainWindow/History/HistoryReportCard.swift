import AppKit
import SwiftUI

/// "Rapor": seçili dönemin kısa özeti. Toplam, mobil/Wi-Fi, önceki dönemle kıyas, en çok kullanan uygulamalar
/// (satır açılınca alan adları) ve alan adları. Hızlı dönem kısayolları ve düz metin kopyalama burada.
struct HistoryReportCard: View {
    let report: HistoryReport?
    /// Gösterilen rapor, şu an istenen dönemin raporu mu (yeni yükleme sürerken eski içerik soluk gösterilir).
    let isCurrent: Bool
    let store: UsageStore
    let selectedPreset: HistoryReportPreset?
    let onPreset: (HistoryReportPreset) -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(spacing: 6) {
                ForEach(HistoryReportPreset.allCases) { preset in
                    HistoryReportChip(title: preset.title, isSelected: selectedPreset == preset) { onPreset(preset) }
                }
            }
            if let report {
                content(report)
                    .opacity(isCurrent ? 1 : 0.5)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Yükleniyor…").foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private var header: some View {
        HStack {
            Text("Rapor").font(.headline)
            Spacer()
            Button(copied ? "Kopyalandı" : "Kopyala", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
                .controlSize(.small)
                .disabled(report == nil || report?.isEmpty == true)
                .help("Raporu düz metin olarak panoya kopyalar")
        }
    }

    @ViewBuilder
    private func content(_ report: HistoryReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(report.period.title).font(.title3.weight(.semibold))
                Text(report.period.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            if report.isEmpty {
                Text("Bu dönemde ağ kaydı yok.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                totals(report)
                Divider()
                appsSection(report)
                if !report.domains.isEmpty {
                    domainsSection(report)
                }
                coverageNote(report)
            }
        }
    }

    private func totals(_ report: HistoryReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Format.bytes(report.total))
                    .font(.title.weight(.bold))
                    .monospacedDigit()
                if let text = report.changeText, let f = report.changeFraction {
                    Label(text, systemImage: f > 0 ? "arrow.up.right" : (f < 0 ? "arrow.down.right" : "equal"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(f > 0.005 ? Color.orange : (f < -0.005 ? Color.green : Color.secondary))
                        .accessibilityLabel("Önceki döneme göre \(text)")
                }
            }
            HistoryShareBar(mobileFraction: report.mobileShare)
            HStack(spacing: 14) {
                LegendValue(color: MediumStyle.mobileColor, title: MediumStyle.mobileName, bytes: report.mobile)
                LegendValue(color: MediumStyle.wifiColor, title: MediumStyle.wifiName, bytes: report.other)
            }
            VStack(alignment: .leading, spacing: 2) {
                if report.previousTotal > 0 {
                    Text(report.period.isComparable
                         ? "Önceki dönem: \(Format.bytes(report.previousTotal))"
                         : "Dün (tamamı): \(Format.bytes(report.previousTotal))")
                }
                if let avg = report.dailyAverage { Text("Günlük ortalama: \(Format.bytes(avg))") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func appsSection(_ report: HistoryReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Uygulamalar").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if report.apps.isEmpty {
                Text("Uygulama kaydı yok.").font(.callout).foregroundStyle(.secondary)
            } else {
                let peak = Double(report.apps.first?.bytes ?? 1)
                let loader = HistoryDetailLoader(store: store, target: .days(from: report.period.fromDay, to: report.period.toDay))
                ForEach(report.apps) { app in
                    HistoryAppRow(app: app, fraction: Double(app.bytes) / max(1, peak), loader: loader)
                }
            }
        }
    }

    private func domainsSection(_ report: HistoryReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alan adları").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            let peak = Double(report.domains.map(\.bytes).max() ?? 1)
            ForEach(report.domains) { domain in
                HistoryReportDomainRow(domain: domain, fraction: Double(domain.bytes) / max(1, peak))
            }
        }
    }

    /// Uygulama dökümü toplamın küçük bir kısmını açıklıyorsa kullanıcıya söyler (yanlış okunmasın).
    @ViewBuilder
    private func coverageNote(_ report: HistoryReport) -> some View {
        if let f = report.attributedFraction, f < 0.9 {
            Text("Uygulama dökümü toplamın \(Format.percent(f))'ini açıklıyor; kalanı uygulamaya atanamayan trafik.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func copy() {
        guard let report else { return }
        let text = report.summaryText { AppCatalog.shared.name(for: $0) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }
}
