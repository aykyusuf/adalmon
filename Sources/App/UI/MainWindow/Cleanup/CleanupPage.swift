import SwiftUI

/// Temizlik sayfası: solda alt bölüm listesi, sağda seçili bölümün içeriği. Seçim `SettingsRouter`'da saklanır.
struct CleanupPage: View {
    @Bindable var router: SettingsRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: MainSection.cleanup.title)
                .padding(.horizontal, 24)
            HStack(alignment: .top, spacing: 16) {
                subsectionList
                BoundedHeight { content }
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 24)
    }

    private var subsectionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(CleanupSubsection.allCases) { subsection in
                    CleanupSubsectionRow(subsection: subsection, isSelected: router.cleanupSubsection == subsection) {
                        router.cleanupSubsection = subsection
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .frame(width: 168)
    }

    @ViewBuilder
    private var content: some View {
        switch router.cleanupSubsection {
        case .smartScan: SmartScanSection(onReview: { router.cleanupSubsection = $0 })
        case .junk: CleanupJunkSection()
        case .dev: CleanupDevSection()
        case .uninstaller: UninstallerSection()
        case .largeOld: LargeOldSection()
        case .duplicates: DuplicatesSection()
        case .privacy: PrivacySection()
        case .spaceLens: SpaceLensSection()
        case .startup: CleanupStartupSection()
        case .maintenance: MaintenanceSection()
        }
    }
}

private struct CleanupSubsectionRow: View {
    let subsection: CleanupSubsection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(subsection.title, systemImage: subsection.symbol)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.14) : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Henüz yazılmamış alt bölümler için ortak "Yakında" kartı.
struct CleanupComingSoon: View {
    let subsection: CleanupSubsection

    var body: some View {
        ContentUnavailableView(subsection.title, systemImage: subsection.symbol,
                               description: Text("Yakında"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }
}
