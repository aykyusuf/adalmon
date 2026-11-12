import SwiftUI

/// Bir bakım konusunun risk düzeyi (yalnızca gösterim; içerik `MaintenanceInfo`da, burada kimliğe göre eşlenir).
enum MaintenanceRisk: Equatable {
    case safe, caution, heavy, discouraged, info

    init(topic: MaintenanceTopic) {
        switch topic.id {
        case "dns-flush": self = .safe
        case "tm-snapshots": self = .caution
        case "spotlight-reindex": self = .heavy
        case "purge": self = .discouraged
        case "periodic": self = .info
        default: self = topic.warning == nil ? .safe : .caution
        }
    }

    var title: String {
        switch self {
        case .safe: "Güvenli"
        case .caution: "Dikkat"
        case .heavy: "Ağır"
        case .discouraged: "Önerilmez"
        case .info: "Bilgi"
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .caution: .orange
        case .heavy: .orange
        case .discouraged: .red
        case .info: .blue
        }
    }

    var symbol: String {
        switch self {
        case .safe: "checkmark.shield.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .heavy: "bolt.fill"
        case .discouraged: "hand.raised.fill"
        case .info: "info.circle.fill"
        }
    }
}

/// Bilgi kartı: ikon, ne işe yaradığı, risk rozeti, notlar ve kopyalanabilir komutlar.
struct MaintenanceTopicCard: View {
    let topic: MaintenanceTopic
    let accent: CleanupAccent
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var risk: MaintenanceRisk { MaintenanceRisk(topic: topic) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: topic.symbol)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.gradient))
                    .shadow(color: accent.deep.opacity(0.35), radius: 3, y: 2)
                    .accessibilityHidden(true)
                Text(topic.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                riskBadge
            }
            Text(topic.summary).font(.callout).foregroundStyle(.primary.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            if !topic.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(topic.notes, id: \.self) { note in
                        Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let warning = topic.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.medium)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10), in: .rect(cornerRadius: 10))
            }
            if topic.commands.isEmpty {
                Label("Elle çalıştırmak gerekmez.", systemImage: "checkmark.circle.fill").font(.caption.weight(.medium)).foregroundStyle(.green)
            } else {
                ForEach(topic.commands) { MaintenanceCommandBlock(command: $0, accent: accent) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(hovered ? 0.08 : 0.05), in: .rect(cornerRadius: 16))
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
        .accessibilityElement(children: .contain)
    }

    private var riskBadge: some View {
        Label(risk.title, systemImage: risk.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(risk.color.opacity(0.16), in: .capsule)
            .foregroundStyle(risk.color)
            .accessibilityLabel("Risk: \(risk.title)")
    }
}

/// Kopyalanabilir komut: açıklama, kod kutusu ve "Komutu kopyala". Kopyalanınca kısa bir onay animasyonu (zıplayan onay işareti,
/// yeşil dolgu) çalışır ve 2 sn sonra eski haline döner. Komut ASLA çalıştırılmaz; yalnızca panoya kopyalanır.
struct MaintenanceCommandBlock: View {
    let command: MaintenanceCommand
    let accent: CleanupAccent
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(command.caption).font(.caption.weight(.medium)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(command.text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(4)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.14), in: .rect(cornerRadius: 10))
            HStack(spacing: 8) {
                if command.needsAdmin {
                    Label("Terminal'de çalıştırman gerekir, yönetici parolası ister.", systemImage: "lock.fill")
                        .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                copyButton
            }
        }
    }

    private var copyButton: some View {
        Button(action: copy) {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .symbolEffect(.bounce, value: reduceMotion ? false : copied)
                    .contentTransition(.symbolEffect(.replace))
                Text(copied ? "Kopyalandı" : "Komutu kopyala")
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(copied ? Color.green : (colorScheme == .dark ? accent.light : accent.deep))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background((copied ? Color.green : accent.base).opacity(0.16), in: .capsule)
            .overlay(Capsule().strokeBorder((copied ? Color.green : accent.base).opacity(0.35), lineWidth: 1))
            .scaleEffect(copied && !reduceMotion ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .help("Komutu panoya kopyalar; çalıştırmaz")
        .accessibilityLabel(copied ? "Kopyalandı" : "Komutu kopyala")
    }

    private func copy() {
        ProcessActions.copy(command.text)
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.35)) { copied = true }
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { copied = false }
        }
    }
}
