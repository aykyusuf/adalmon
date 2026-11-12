import SwiftUI

/// Uygulama başına canlı ağ tüketimi: aralık seçici (60 sn … 1 sa), ağ süzgeci, ↓/↑, anlık hız ve satırdan
/// anında hız sınırı / engel (Mobilde · Wi-Fi'de · Her yerde; mevcut altyapı, geri alınabilir). Mobil, Ağ kullanımı ve Genel bakış sayfaları kullanır.
///
/// Pil: veri yalnızca görünüm ekrandayken (`.task`) en fazla saniyede bir okunur; görünüm kapanınca görev biter.
/// Kaynak, ölçüm adımının zaten doldurduğu bellek içi geçmiştir; yeni örnekleyici ya da zamanlayıcı yoktur.
struct LiveAppUsageList: View {
    /// Satır kaynağı: (aralık, süzgeç) → büyükten küçüğe satırlar.
    struct Source {
        var rows: @MainActor (LiveRange, LiveInterface) -> [LiveAppUsage]
        /// Bugünün toplamları (yalnızca `showsToday` açıkken seçilebilir; ↓/↑ ayrımı yok).
        var today: (@MainActor (LiveInterface) -> [LiveAppUsage])? = nil
        /// Liste kullanıcıya görünüyor mu? Değilse (ana pencere küçültülmüş/örtülü, panel kapalı) saniyelik okuma ve
        /// durum yazımı atlanır; pencere görünür olunca en geç ~1 sn içinde yenilenir (pil).
        var isActive: @MainActor () -> Bool = { true }

        @MainActor
        static func live(_ model: AppModel) -> Source {
            Source(rows: { [weak model] range, interface in model?.usage.liveRows(range: range, interface: interface) ?? [] },
                   today: { [weak model] interface in model?.usage.todayRows(interface: interface) ?? [] },
                   isActive: { [weak model] in model.map { $0.mainWindowVisible || $0.panelVisible } ?? false })
        }

        /// Önizleme/test: aralıktan bağımsız sabit satırlar.
        static func fixed(_ rows: [LiveAppUsage]) -> Source { Source(rows: { _, _ in rows }, today: { _ in rows }) }
    }

    /// Seçili zaman penceresi: canlı aralık ya da bugün.
    enum Window: Hashable {
        case range(LiveRange)
        case today

        var title: String {
            switch self {
            case .range(let r): r.title
            case .today: "Bugün"
            }
        }

        var phrase: String {
            switch self {
            case .range(let r): r.phrase
            case .today: "bugün"
            }
        }
    }

    let title: String
    let source: Source
    let controls: LiveAppControls
    /// Gösterilecek süzgeçler; tek elemanlıysa süzgeç seçici gizlenir (Mobil sayfası: yalnız `.mobile`).
    let interfaces: [LiveInterface]
    /// Görünen en fazla satır; fazlası "Tümünü göster" ile açılır. `nil` = sınırsız.
    let maxRows: Int?
    /// Daha sıkı yerleşim (Genel bakış kartı).
    let compact: Bool
    /// Hız sınırı yalnızca mobil veride mi uygulansın (Mobil sayfası).
    let limitsOnlyOnMobile: Bool
    /// Sayfanın varsayılan engel kapsamı (Mobil sayfası: `.mobile`); şu an yalnızca bilgi amaçlı.
    let preferredBlockScope: BlockScope?
    /// Aralık seçicide "Bugün" seçeneği (Genel bakış).
    let showsToday: Bool
    /// Başlık yerine gösterilecek görünüm (Genel bakış: başlık + [Ağ | CPU | Bellek]).
    let headerLeading: AnyView?
    /// Verilirse "Tümünü göster" listeyi büyütmek yerine bunu çağırır (kaydırmasız sayfalar).
    let moreAction: (() -> Void)?

    @State private var window: Window
    @State private var interface: LiveInterface
    @State private var rows: [LiveAppUsage] = []
    @State private var loaded = false
    @State private var showAll = false
    @State private var undo: LiveAppUndo?
    @State private var pendingBlock: PendingBlock?

    /// Onay bekleyen engel (sistem süreci ya da "her yerde").
    private struct PendingBlock: Equatable {
        var app: String
        var scope: BlockScope
    }

    init(title: String = "Şu an en çok kullananlar", source: Source, controls: LiveAppControls,
         interfaces: [LiveInterface] = LiveInterface.allCases, maxRows: Int? = 8, compact: Bool = false,
         limitsOnlyOnMobile: Bool = false, preferredBlockScope: BlockScope? = nil, initialRange: LiveRange = .sec60, initialRows: [LiveAppUsage] = [],
         showsToday: Bool = false, initialToday: Bool = false, headerLeading: AnyView? = nil, moreAction: (() -> Void)? = nil) {
        self.title = title
        self.source = source
        self.controls = controls
        self.interfaces = interfaces.isEmpty ? [.all] : interfaces
        self.maxRows = maxRows
        self.compact = compact
        self.limitsOnlyOnMobile = limitsOnlyOnMobile
        self.preferredBlockScope = preferredBlockScope
        self.showsToday = showsToday && source.today != nil
        self.headerLeading = headerLeading
        self.moreAction = moreAction
        _window = State(initialValue: initialToday && self.showsToday ? .today : .range(initialRange))
        _interface = State(initialValue: self.interfaces[0])
        _rows = State(initialValue: initialRows)
        _loaded = State(initialValue: !initialRows.isEmpty)
    }

    private struct RefreshKey: Hashable { var window: Window; var interface: LiveInterface }

    private var windows: [Window] { LiveRange.allCases.map(Window.range) + (showsToday ? [.today] : []) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            header
            if let undo { undoStrip(undo) }
            content
            if !controls.filterReady() {
                Label("Sınır ve engel için ağ filtresinin kurulu olması gerekir.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(compact ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: compact ? 12 : 16))
        .task(id: RefreshKey(window: window, interface: interface)) { await refreshWhileVisible() }
        .task(id: undo) {
            guard undo != nil else { return }
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { withAnimation { undo = nil } }
        }
        .confirmationDialog(
            pendingBlock.map { LiveAppActionMapper.confirmation(scope: $0.scope, app: $0.app).title } ?? "",
            isPresented: Binding(get: { pendingBlock != nil }, set: { if !$0 { pendingBlock = nil } }),
            titleVisibility: .visible,
            presenting: pendingBlock
        ) { pending in
            Button("\(pending.scope.title) engelle", role: .destructive) { apply(.block(pending.scope), app: pending.app, confirmed: true) }
        } message: { pending in
            Text(LiveAppActionMapper.confirmation(scope: pending.scope, app: pending.app).message)
        }
    }

    // MARK: Başlık

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                leading
                Spacer(minLength: 8)
                pickers
            }
            VStack(alignment: .leading, spacing: 8) {
                leading
                HStack(spacing: 10) { pickers }
            }
        }
    }

    @ViewBuilder private var leading: some View {
        if let headerLeading { headerLeading } else { titleLabel }
    }

    private var titleLabel: some View {
        Label(title, systemImage: "gauge.with.dots.needle.67percent")
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var pickers: some View {
        if interfaces.count > 1 {
            Picker("Ağ", selection: $interface) {
                ForEach(interfaces) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(compact ? .small : .regular)
        }
        if compact {
            // Kompakt: "son: [1 sa ▾]" — dar başlıkta yer kaplamaz; kayıt notu ipucunda.
            Picker("son:", selection: $window) {
                ForEach(windows, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .controlSize(.small)
            .help(window == .range(.now) ? "Şu an saniyede ne kadar (son \(LiveUsageHistory.rateWindow) sn ortalaması)" : window == .range(.sec60) ? "Son 60 saniyenin trafiği" : "Adalmon açıkken ölçülen trafik; \(window.phrase).")
        } else {
            Picker("Aralık", selection: $window) {
                ForEach(windows, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.regular)
        }
    }

    private func undoStrip(_ record: LiveAppUndo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
            Text(record.message).font(.callout).lineLimit(1)
            Spacer(minLength: 8)
            Button("Geri al") {
                LiveAppActionMapper.undo(record, controls: controls)
                withAnimation { undo = nil }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.10), in: .rect(cornerRadius: 8))
        .transition(.opacity)
    }

    // MARK: Satırlar

    @ViewBuilder private var content: some View {
        if rows.isEmpty {
            Text(loaded ? emptyText : "Ölçülüyor…")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, compact ? 2 : 6)
        } else {
            let visible = visibleRows
            let peak = Double(max(1, rows.first?.bytes ?? 1))
            VStack(spacing: compact ? 6 : 10) {
                ForEach(visible) { row in
                    LiveAppRow(row: row, fraction: Double(row.bytes) / peak, tint: tint, compact: compact, showsSplit: window != .today, perSecond: window == .range(.now),
                               limit: controls.limit(row.app), block: controls.blockScope(row.app),
                               allowedScopes: LiveAppActionMapper.allowedScopes(app: row.app), preferredScope: preferredBlockScope,
                               onCommand: { apply($0, app: row.app, confirmed: false) })
                }
            }
            if let maxRows, rows.count > maxRows {
                if let moreAction {
                    Button("Tümü (\(rows.count))", action: moreAction)
                        .buttonStyle(.link)
                        .font(.caption)
                } else {
                    Button(showAll ? "Daha az göster" : "Tümünü göster (\(rows.count))") { showAll.toggle() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            if window != .range(.sec60), !compact {
                Text("Adalmon açıkken ölçülen trafik; \(window.phrase).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var visibleRows: [LiveAppUsage] {
        guard let maxRows, !showAll else { return rows }
        return Array(rows.prefix(maxRows))
    }

    private var tint: Color { interface == .mobile ? .orange : .cyan }

    private var emptyText: String {
        let phrase = window.phrase
        return interface == .mobile ? "\(phrase.prefix(1).uppercased())\(phrase.dropFirst()) mobil veride uygulama trafiği yok."
            : "\(phrase.prefix(1).uppercased())\(phrase.dropFirst()) kayda değer trafik yok."
    }

    /// Saniyelik turda satırlar okunsun mu: görünürken her tur; görünmezken yalnızca ilk yükleme (iskelet kalmasın).
    nonisolated static func shouldRefresh(active: Bool, loaded: Bool) -> Bool { active || !loaded }

    private func refreshWhileVisible() async {
        while !Task.isCancelled {
            guard Self.shouldRefresh(active: source.isActive(), loaded: loaded) else {
                try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(300))
                continue
            }
            let next: [LiveAppUsage] = switch window {
            case .range(let range): source.rows(range, interface)
            case .today: source.today?(interface) ?? []
            }
            if next != rows { rows = next }
            if !loaded { loaded = true }
            try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(300))
        }
    }

    private func apply(_ command: LiveAppCommand, app: String, confirmed: Bool) {
        if !confirmed, LiveAppActionMapper.needsConfirmation(command, app: app), case .block(let scope) = command {
            pendingBlock = PendingBlock(app: app, scope: scope)
            return
        }
        if let record = LiveAppActionMapper.apply(command, app: app, onlyOnMobile: limitsOnlyOnMobile, controls: controls) {
            withAnimation { undo = record }
        }
    }
}

/// Canlı listenin tek satırı: simge, ad + rozetler, çubuk, toplam (↓/↑), anlık hız, hız sınırı menüsü ve engel menüsü.
private struct LiveAppRow: View {
    let row: LiveAppUsage
    let fraction: Double
    let tint: Color
    let compact: Bool
    /// ↓/↑ ayrımı biliniyor mu (Bugün toplamlarında yok).
    let showsSplit: Bool
    /// Anlık pencere: değerler saniye başına (B/s) gösterilir, ayrı hız sütunu gizlenir.
    var perSecond = false
    let limit: AppLimit?
    let block: BlockScope?
    let allowedScopes: [BlockScope]
    let preferredScope: BlockScope?
    let onCommand: (LiveAppCommand) -> Void

    @State private var showCustom = false
    @State private var customKB = ""

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            Image(nsImage: AppCatalog.shared.icon(for: row.app))
                .resizable()
                .frame(width: compact ? 18 : 22, height: compact ? 18 : 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(AppCatalog.shared.name(for: row.app))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ForEach(LiveAppActionMapper.badges(limit: limit, block: block), id: \.self) { badge in
                        Text(badge.text)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .foregroundStyle(badge.isBlock ? .red : .orange)
                            .background((badge.isBlock ? Color.red : .orange).opacity(0.15), in: .capsule)
                            .fixedSize()
                    }
                }
                UsageBar(fraction: fraction, tint: tint.opacity(0.7), height: compact ? 3 : 4)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(perSecond ? Format.rate(Double(row.bytes)) : Format.bytes(row.bytes))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
                if !compact && showsSplit {
                    Text(perSecond ? "↓\(Format.rate(Double(row.down))) ↑\(Format.rate(Double(row.up)))" : "↓\(Format.bytes(row.down)) ↑\(Format.bytes(row.up))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .frame(minWidth: compact ? 64 : 110, alignment: .trailing)
            .help(showsSplit ? "İndirme ↓\(Format.bytes(row.down)) · Yükleme ↑\(Format.bytes(row.up))" : "Bugünkü toplam (↓ + ↑)")
            if !perSecond {
            Text(row.rate > 0 ? Format.rate(Double(row.rate)) : "–")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: compact ? 58 : 70, alignment: .trailing)
                .help("Anlık hız (son \(LiveUsageHistory.rateWindow) sn ortalaması)")
            }
            limitMenu
            blockMenu
        }
        .accessibilityElement(children: .contain)
        .contextMenu {
            Menu("Hız sınırı") { limitItems }
            Menu("Engelle") { blockItems }
        }
    }

    private var limitMenu: some View {
        Menu {
            limitItems
        } label: {
            Image(systemName: "speedometer")
                .foregroundStyle(limit != nil ? .orange : .secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Hız sınırı…")
        .accessibilityLabel("Hız sınırı")
        .popover(isPresented: $showCustom, arrowEdge: .bottom) {
            HStack {
                TextField("KB/s", text: $customKB)
                    .frame(width: 80)
                    .onSubmit(applyCustom)
                Text("KB/s")
                Button("Uygula", action: applyCustom)
                    .keyboardShortcut(.defaultAction)
                    .disabled(LiveAppActionMapper.customBytesPerSec(kilobytesText: customKB) == nil)
            }
            .padding(12)
        }
    }

    /// Hız sınırı: aynı değer indirme ve yüklemeye birlikte uygulanır (ayrıca sorulmaz).
    @ViewBuilder private var limitItems: some View {
        Section(limit.map { "Şu an: \(LiveAppActionMapper.limitSummary($0))" } ?? "Hız sınırı (↓ ve ↑ birlikte)") {
            ForEach(LiveAppActionMapper.presets, id: \.self) { value in
                let current = limit?.downBytesPerSec == value && limit?.upBytesPerSec == value
                Button {
                    onCommand(.limit(bytesPerSec: value))
                } label: {
                    if current { Label(AppModel.rateText(value), systemImage: "checkmark") } else { Text(AppModel.rateText(value)) }
                }
            }
            Menu("Yalnızca indirme ↓") {
                ForEach(LiveAppActionMapper.presets, id: \.self) { value in
                    Button(AppModel.rateText(value)) { onCommand(.limitDown(bytesPerSec: value)) }
                }
            }
            Menu("Yalnızca yükleme ↑") {
                ForEach(LiveAppActionMapper.presets, id: \.self) { value in
                    Button(AppModel.rateText(value)) { onCommand(.limitUp(bytesPerSec: value)) }
                }
            }
            Button("Özel…") {
                customKB = limit?.downBytesPerSec.map { String($0 / 1024) } ?? ""
                showCustom = true
            }
            if limit != nil {
                Button("Sınırı kaldır", systemImage: "xmark.circle") { onCommand(.clearLimit) }
            }
        }
    }

    /// Engel: nerede engelleneceğini sorar (Mobilde / Wi-Fi'de / Her yerde); engelliyse durumu ve "Engeli kaldır"ı gösterir.
    private var blockMenu: some View {
        Menu {
            blockItems
        } label: {
            Image(systemName: block != nil ? "hand.raised.slash.fill" : "hand.raised")
                .foregroundStyle(block != nil ? .red : .secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(block.map { "\($0.badge) — değiştir ya da kaldır" } ?? "Engelle: mobilde, Wi-Fi/kablolu ağda ya da her yerde")
        .accessibilityLabel(block?.badge ?? "Engelle")
    }

    @ViewBuilder private var blockItems: some View {
        Section(block.map { "Şu an: \($0.badge)" } ?? "Engelle") {
            ForEach(BlockScope.allCases) { scope in
                Button {
                    onCommand(.block(scope))
                } label: {
                    if scope == block { Label(blockTitle(scope), systemImage: "checkmark") } else { Text(blockTitle(scope)) }
                }
                .disabled(!allowedScopes.contains(scope))
            }
            if allowedScopes.count < BlockScope.allCases.count {
                Text("Sistem hizmeti: yalnızca mobilde engellenebilir")
            }
            if block != nil {
                Button("Engeli kaldır", systemImage: "hand.raised.slash") { onCommand(.unblock) }
            }
        }
    }

    private func blockTitle(_ scope: BlockScope) -> String {
        let base = switch scope {
        case .mobile: "Mobil veride"
        case .wifi: "Wi-Fi / kabloluda"
        case .everywhere: "Her yerde"
        }
        return base
    }

    private func applyCustom() {
        guard let bytes = LiveAppActionMapper.customBytesPerSec(kilobytesText: customKB) else { return }
        showCustom = false
        onCommand(.limit(bytesPerSec: bytes))
    }
}
