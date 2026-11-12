import SwiftUI

/// Tarayıcı başına bölüm: marka logolu başlık + durum kartı ya da Geçmiş / Çerezler seçim kartları (marka renkli).
struct PrivacyBrowserGroup: View {
    let vm: BrowserPrivacyViewModel
    let browser: PrivacyBrowser
    let scan: BrowserPrivacyScan
    let isBusy: Bool
    let onHelp: (AccessReason) -> Void

    private var accent: CleanupAccent { browser.brandAccent }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            switch scan.state {
            case .running: runningCard
            case .noAccess: noAccessCard
            case .notFound: EmptyView()
            case .scanned: scannedCards
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            PrivacyBrowserLogo(browser: browser, size: 28)
            Text(browser.title).font(.headline)
            Spacer(minLength: 8)
            Text(trailingText).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var trailingText: String {
        switch scan.state {
        case .notFound: "Bulunamadı"
        case .scanned: browser == .safari ? "" : "\(scan.profileCount) profil"
        case .running, .noAccess: ""
        }
    }

    private var runningCard: some View {
        CleanupResultCard(
            symbol: "exclamationmark.triangle.fill", title: BrowserPrivacyRules.closeFirstText(browser),
            subtitle: "\(browser.shortName) açıkken dosyaları kilitli olabilir; bu yüzden hiçbir şey listelenmez ve silinmez.",
            accent: .privacyWarning
        ) {
            Button("Tekrar tara") { vm.scan() }.buttonStyle(.borderless).disabled(isBusy)
        }
    }

    private var noAccessCard: some View {
        CleanupResultCard(symbol: "lock.fill", title: AccessReason.fullDiskAccess.title,
                          subtitle: "\(browser.shortName) verisini okumak için izin gerekir.", accent: .privacyWarning) {
            HStack(spacing: 8) {
                if let button = AccessReason.fullDiskAccess.buttonTitle {
                    Button(button) { vm.access.openSettings(for: .fullDiskAccess) }.buttonStyle(.borderless)
                }
                Button("Nasıl?") { onHelp(.fullDiskAccess) }.buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var scannedCards: some View {
        if scan.files.isEmpty {
            CleanupResultCard(symbol: "checkmark.seal.fill", title: "Temiz",
                              subtitle: "Silinecek geçmiş ya da çerez yok.", accent: accent)
        } else {
            ForEach(PrivacyDataKind.allCases) { kind in kindCard(kind) }
        }
    }

    private func kindCard(_ kind: PrivacyDataKind) -> some View {
        let available = scan.has(kind)
        let isOn = vm.selected(browser).contains(kind)
        return CleanupResultCard(
            symbol: kind == .history ? "clock.arrow.circlepath" : "person.crop.circle.badge.xmark",
            title: kind.title,
            subtitle: kind == .history ? "Ziyaret edilen sayfalar, en çok gidilen siteler" : "Tüm sitelerden çıkış yapılır",
            sizeText: available ? Format.bytes(scan.bytes(of: kind)) : "Yok",
            accent: accent, selection: isOn ? .all : .none, isEnabled: available && !isBusy,
            onToggle: { vm.toggle(kind, in: browser) }
        )
    }
}

extension CleanupAccent {
    /// Uyarı kartları (açık tarayıcı, erişim yok).
    static let privacyWarning = CleanupAccent(hue: 0.09, saturation: 0.85, brightness: 0.96)
}
