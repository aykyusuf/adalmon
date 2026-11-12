import SwiftUI

/// Kartın onay kutusu durumu: hiçbiri / bir kısmı / hepsi.
enum CleanupSelectionState: Equatable {
    case none, partial, all

    init(selected: Int, total: Int) {
        self = selected <= 0 ? .none : selected >= total ? .all : .partial
    }

    fileprivate var symbol: String {
        switch self {
        case .none: "square"
        case .partial: "minus.square.fill"
        case .all: "checkmark.square.fill"
        }
    }

    fileprivate var spoken: String {
        switch self {
        case .none: "seçili değil"
        case .partial: "bir kısmı seçili"
        case .all: "hepsi seçili"
        }
    }
}

/// Sonuç kartı: ikon kutusu, başlık, tek satır açıklama, boyut ve onay kutusu. `detail` verilirse kart açılır
/// (`isExpanded`); verilmezse düz kart. `accessory` boyutun yanına küçük bir eylem koyar (ör. "İncele →").
/// `onToggle` nil ise onay kutusu yoktur (yalnızca bilgi / incele kartı).
struct CleanupResultCard<Detail: View, Accessory: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    var sizeText: String?
    let accent: CleanupAccent
    var selection: CleanupSelectionState = .none
    var isEnabled = true
    var onToggle: (() -> Void)?
    @Binding var isExpanded: Bool
    private let detail: Detail?
    private let accessory: Accessory
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(symbol: String, title: String, subtitle: String, sizeText: String? = nil, accent: CleanupAccent,
         selection: CleanupSelectionState = .none, isEnabled: Bool = true, onToggle: (() -> Void)? = nil,
         isExpanded: Binding<Bool> = .constant(false),
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder detail: () -> Detail) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.sizeText = sizeText
        self.accent = accent
        self.selection = selection
        self.isEnabled = isEnabled
        self.onToggle = onToggle
        _isExpanded = isExpanded
        self.accessory = accessory()
        self.detail = detail()
    }

    private var hasDetail: Bool { Detail.self != EmptyView.self }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded, hasDetail, let detail {
                detail
                    .padding(.horizontal, 14).padding(.bottom, 12).padding(.leading, onToggle == nil ? 46 : 74)
                    .transition(.opacity)
            }
        }
        .background(Color.primary.opacity(hovered ? 0.08 : 0.05), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(selection == .none ? Color.clear : accent.base.opacity(0.35), lineWidth: 1))
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.05), value: isExpanded)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let onToggle {
                Button(action: onToggle) {
                    Image(systemName: selection.symbol).font(.system(size: 18))
                        .foregroundStyle(selection == .none ? Color.secondary : accent.base)
                        .frame(width: 22)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.35)
                .accessibilityLabel(title)
                .accessibilityValue(selection.spoken)
            }
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(accent.gradient))
                .shadow(color: accent.deep.opacity(0.35), radius: 3, y: 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory
            if let sizeText {
                Text(sizeText).font(.callout.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
            }
            if hasDetail {
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0)).frame(width: 14)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(.rect)
        .onTapGesture { if hasDetail { isExpanded.toggle() } }
        .accessibilityAddTraits(hasDetail ? .isButton : [])
        .accessibilityHint(hasDetail ? (isExpanded ? "Ayrıntıyı kapat" : "Ayrıntıyı aç") : "")
    }
}

extension CleanupResultCard where Detail == EmptyView {
    init(symbol: String, title: String, subtitle: String, sizeText: String? = nil, accent: CleanupAccent,
         selection: CleanupSelectionState = .none, isEnabled: Bool = true, onToggle: (() -> Void)? = nil,
         @ViewBuilder accessory: () -> Accessory) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, sizeText: sizeText, accent: accent, selection: selection,
                  isEnabled: isEnabled, onToggle: onToggle, accessory: accessory) { EmptyView() }
    }
}

extension CleanupResultCard where Accessory == EmptyView {
    init(symbol: String, title: String, subtitle: String, sizeText: String? = nil, accent: CleanupAccent,
         selection: CleanupSelectionState = .none, isEnabled: Bool = true, onToggle: (() -> Void)? = nil,
         isExpanded: Binding<Bool> = .constant(false), @ViewBuilder detail: () -> Detail) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, sizeText: sizeText, accent: accent, selection: selection,
                  isEnabled: isEnabled, onToggle: onToggle, isExpanded: isExpanded, accessory: { EmptyView() }, detail: detail)
    }
}

extension CleanupResultCard where Detail == EmptyView, Accessory == EmptyView {
    init(symbol: String, title: String, subtitle: String, sizeText: String? = nil, accent: CleanupAccent,
         selection: CleanupSelectionState = .none, isEnabled: Bool = true, onToggle: (() -> Void)? = nil) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, sizeText: sizeText, accent: accent, selection: selection,
                  isEnabled: isEnabled, onToggle: onToggle, accessory: { EmptyView() }) { EmptyView() }
    }
}

/// Açılan kart içindeki öğe satırı: onay kutusu, ad, ikinci satır, boyut.
struct CleanupItemRow: View {
    let title: String
    var subtitle: String?
    let sizeText: String
    var isSelected: Bool
    var isEnabled = true
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle(title, isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox).labelsHidden().disabled(!isEnabled)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1).truncationMode(.middle)
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            Text(sizeText).font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
