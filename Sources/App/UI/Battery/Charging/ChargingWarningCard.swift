import SwiftUI

struct ChargingWarningCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Deneysel özellik", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("""
            Şarj sınırı, pilin şarjını donanım düzeyinde (SMC) durdurur. Bunun için yönetici ayrıcalıklı küçük bir yardımcı \
            (AdalmonHelper) kurulur ve Sistem Ayarları'nda onayınız gerekir. Apple bu anahtarları belgelemez; macOS güncellemesi \
            anahtarları değiştirebilir. Bu yüzden yardımcı yalnızca bu Mac'te var olduğunu doğruladığı anahtarlara yazar.
            """)
            Text("""
            Güvenlik: pil %\(HelperConstants.hardFloorPercent)'in altındaysa şarj her zaman serbesttir; yardımcı kapanır ya da çökerse şarj \
            serbest bırakılır; "Tümünü kapat" her şeyi varsayılana döndürür.
            """)
            .foregroundStyle(.secondary)
        }
        .font(.callout)
        .batteryCard()
    }
}
