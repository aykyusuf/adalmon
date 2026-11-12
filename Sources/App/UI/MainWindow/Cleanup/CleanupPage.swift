import SwiftUI

/// Temizlik sayfası: solda sade bölüm listesi (renkli ikon kutusu + ad), sağda seçili bölümün sihirbazı. Seçim `SettingsRouter`'da saklanır.
/// Bölüm değişince içerik yumuşakça solup yenisi gelir ("Hareketi azalt" açıkken anlık).
struct CleanupPage: View {
    @Bindable var router: SettingsRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: MainSection.cleanup.title)
                .padding(.horizontal, 24)
            HStack(alignment: .top, spacing: 18) {
                subsectionList
                BoundedHeight { content }
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 24)
        // Sayfadan çıkınca süren tarama durur (pil); sonuçlar yönlendiricideki modelde kalır.
        .onDisappear { router.smartScan.cancel() }
    }

    private var subsectionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(CleanupSubsection.allCases) { subsection in
                    CleanupSubsectionRow(subsection: subsection, isSelected: router.cleanupSubsection == subsection,
                                         namespace: selectionNamespace) { select(subsection) }
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
        .frame(width: 176)
    }

    private func select(_ subsection: CleanupSubsection) {
        guard subsection != router.cleanupSubsection else { return }
        if reduceMotion {
            router.cleanupSubsection = subsection
        } else {
            withAnimation(.spring(duration: 0.35, bounce: 0.1)) { router.cleanupSubsection = subsection }
        }
    }

    private var content: some View {
        sectionContent
            .id(router.cleanupSubsection)
            .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 10)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch router.cleanupSubsection {
        case .smartScan: SmartScanSection(model: router.smartScan, onReview: { router.cleanupSubsection = $0 })
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

/// Bölüm listesi satırı: bölüm renginde küçük ikon kutusu; seçiliyken aynı kapsül bölümler arasında kayar.
private struct CleanupSubsectionRow: View {
    let subsection: CleanupSubsection
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: subsection.symbol)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(subsection.accent.gradient))
                    .shadow(color: subsection.accent.deep.opacity(isSelected ? 0.4 : 0), radius: 3, y: 2)
                    .saturation(isSelected || hovered ? 1 : 0.75)
                Text(subsection.title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(subsection.accent.base.opacity(0.16))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovered {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
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
