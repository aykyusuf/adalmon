import SwiftUI

// Codex "ücretsiz sıfırlama hakları" bölümü: YALNIZCA bilgi. Düğme/eylem yoktur; hak kullanılamaz ya da tüketilemez.

extension LimitResetCredit {
    /// "Haftalık + 5 saatlik tam sıfırlama"; bilinmeyen tür için başlık ya da genel metin.
    var typeText: String {
        switch resetType {
        case "codexRateLimits": "Haftalık + 5 saatlik tam sıfırlama"
        default: "Limit sıfırlama"
        }
    }

    var statusText: String {
        switch status {
        case "available": "Kullanılabilir"
        case "redeeming": "Kullanılıyor"
        case "redeemed": "Kullanıldı"
        default: "Bilinmiyor"
        }
    }

    static let dateStyle = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: "tr_TR"))

    var grantedText: String? { grantedAt.map { "Verildi: \($0.formatted(Self.dateStyle))" } }

    /// "Son kullanma: 20 Kas 2026 · 8 gün kaldı"; süresiz hak için nil.
    func expiryText(now: Date) -> String? {
        guard let expiresAt else { return nil }
        let date = "Son kullanma: \(expiresAt.formatted(Self.dateStyle))"
        return "\(date) · \(remainingText(now: now) ?? "")"
    }

    /// "8 gün kaldı" / "5 sa kaldı" / "Süresi doldu".
    func remainingText(now: Date) -> String? {
        guard let expiresAt else { return nil }
        let seconds = expiresAt.timeIntervalSince(now)
        guard seconds > 0 else { return "Süresi doldu" }
        let days = Int(seconds / 86_400)
        if days >= 1 { return "\(days) gün kaldı" }
        return "\(max(1, Int(seconds / 3600))) sa kaldı"
    }
}

struct LimitResetCreditsSection: View {
    let credits: [LimitResetCredit]
    let now: Date

    var body: some View {
        if !credits.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sıfırlama hakları").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(credits.enumerated()), id: \.offset) { _, credit in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(credit.title ?? credit.typeText).font(.callout.weight(.semibold)).lineLimit(2)
                            Spacer(minLength: 4)
                            LimitChip(text: credit.statusText, color: credit.status == "available" ? .green : .secondary)
                        }
                        Text(credit.typeText).font(.caption).foregroundStyle(.secondary)
                        if let detail = credit.detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        HStack(spacing: 10) {
                            if let granted = credit.grantedText { Text(granted) }
                            if let expiry = credit.expiryText(now: now) { Text(expiry) }
                        }
                        .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
            .accessibilityElement(children: .combine)
        }
    }
}
