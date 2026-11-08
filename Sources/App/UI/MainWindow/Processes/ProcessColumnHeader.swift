import SwiftUI
import UniformTypeIdentifiers

/// Görev Yöneticisi gibi sütun başlığı: üstte sistem toplamı ("%23"), altında sütun adı; tıklayınca sıralar. Hücre toplam yüküne göre tonlanır.
/// Sütun genişlikleri satırlarla aynı `ProcessTableColumns`tan gelir. Başlıklar sürüklenerek yeniden sıralanır (bırakma çizgisi);
/// sağ tık menüsü sola/sağa taşıma, gösterme/gizleme ve varsayılana sıfırlama sunar (sürüklemesiz erişim de buradan).
struct ProcessColumnHeader: View {
    let columns: ProcessTableColumns
    let totals: ProcessTotals
    let sortColumn: ProcessColumn
    let sortAscending: Bool
    let onSort: (ProcessColumn) -> Void
    @Binding var layout: ProcessColumnLayout
    /// Sütunlara ayrılabilen genişlik (görünürlük bu genişliğe göre değerlendirilir).
    let contentWidth: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragging: ProcessColumn?
    @State private var indicator: ColumnDropIndicator?

    var body: some View {
        HStack(spacing: 0) {
            Button { dragging = nil; onSort(.name) } label: {
                HStack(spacing: 4) {
                    Text("Ad").font(.callout.weight(.medium))
                    indicator(for: .name)
                }
                .padding(.leading, 40)
                .frame(width: columns.nameWidth, height: ProcessTableLayout.headerHeight, alignment: .bottomLeading)
                .padding(.bottom, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ad, sırala")
            .overlay(alignment: .trailing) { dropLine(visible: indicator?.column == .name) }
            .onDrop(of: [.plainText], delegate: ColumnDropDelegate(target: .name, width: columns.nameWidth, dragging: $dragging,
                                                                   indicator: $indicator, onMove: move))
            .contextMenu { ProcessColumnsMenu(layout: $layout, column: .name, contentWidth: contentWidth) }
            ForEach(columns.entries) { entry in
                Button { dragging = nil; onSort(entry.column) } label: { cell(entry) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.column.isMetric ? "\(entry.column.title), toplam \(total(entry.column)), sırala" : "\(entry.column.title), sırala")
                    .accessibilityAction(named: "Sola taşı") { moveStep(entry.column, left: true) }
                    .accessibilityAction(named: "Sağa taşı") { moveStep(entry.column, left: false) }
                    .overlay(alignment: indicator?.before == true ? .leading : .trailing) {
                        dropLine(visible: indicator?.column == entry.column)
                    }
                    .onDrag {
                        dragging = entry.column
                        return NSItemProvider(object: entry.column.rawValue as NSString)
                    } preview: {
                        Text(entry.column.title)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.regularMaterial, in: .capsule)
                    }
                    .onDrop(of: [.plainText], delegate: ColumnDropDelegate(target: entry.column, width: entry.width, dragging: $dragging,
                                                                           indicator: $indicator, onMove: move))
                    .contextMenu { ProcessColumnsMenu(layout: $layout, column: entry.column, contentWidth: contentWidth) }
            }
            Spacer(minLength: 0)
        }
        .frame(height: ProcessTableLayout.headerHeight)
    }

    private func cell(_ entry: ProcessTableColumns.Entry) -> some View {
        let column = entry.column
        let t = column.isMetric
            ? HeatTint.quantized(HeatTint.intensity(column: column, value: totalValue(column), memoryTotal: Double(totals.memoryTotal)))
            : 0
        return VStack(alignment: .trailing, spacing: 2) {
            Text(total(column))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: total(column))
            HStack(spacing: 3) {
                indicator(for: column)
                Text(column.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: entry.width, height: ProcessTableLayout.headerHeight, alignment: .trailing)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            $0.background(HeatTint.color(intensity: t, dark: scheme == .dark))
        }
        // Yalnızca sürükleme başlığın üstündeyken soluk (başlık dışında iptal edilen sürükleme geri bildirim vermez).
        .opacity(dragging == column && indicator != nil ? 0.45 : 1)
        .contentShape(.rect)
    }

    /// Bırakma göstergesi: hedef hücrenin bırakılacak kenarında vurgu renginde ince çizgi.
    @ViewBuilder
    private func dropLine(visible: Bool) -> some View {
        if visible {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 3)
                .padding(.vertical, 6)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func move(_ column: ProcessColumn, _ target: ProcessColumn, before: Bool) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            if before { layout.move(column, before: target) } else { layout.move(column, after: target) }
        }
    }

    private func moveStep(_ column: ProcessColumn, left: Bool) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            if left { layout.moveLeft(column, width: contentWidth) } else { layout.moveRight(column, width: contentWidth) }
        }
    }

    @ViewBuilder
    private func indicator(for column: ProcessColumn) -> some View {
        if sortColumn == column {
            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func totalValue(_ column: ProcessColumn) -> Double {
        switch column {
        case .cpu: totals.cpu
        case .memory: Double(totals.memoryUsed)
        case .disk: totals.disk
        case .network: totals.network
        case .gpu: totals.gpu
        case .energy: totals.energy
        case .name, .category, .processCount, .pid: 0
        }
    }

    private func total(_ column: ProcessColumn) -> String {
        switch column {
        case .cpu: ResourceFormat.percent(totals.cpu)
        case .memory: "%\(Int((totals.memoryFraction * 100).rounded()))"
        case .disk: Format.rate(totals.disk)
        case .network: Format.rate(totals.network)
        case .gpu: ResourceFormat.percent(totals.gpu)
        case .energy: ResourceFormat.watts(totals.energy)
        case .name, .category, .processCount, .pid: ""
        }
    }
}

/// Sürüklenen sütunun bırakılacağı yer: hedef sütun ve onun önü mü arkası mı.
struct ColumnDropIndicator: Equatable {
    var column: ProcessColumn
    var before: Bool
}

/// Başlık hücresine bırakma: hücrenin sol yarısı = önüne, sağ yarısı = arkasına. Ad hücresi = en başa.
/// Gösterge yalnızca giriş/güncelleme ile kurulur, çıkış ve bırakmada temizlenir (başlık dışında iptal edilen sürükleme iz bırakmaz).
struct ColumnDropDelegate: DropDelegate {
    let target: ProcessColumn
    let width: CGFloat
    @Binding var dragging: ProcessColumn?
    @Binding var indicator: ColumnDropIndicator?
    let onMove: (ProcessColumn, ProcessColumn, Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if indicator?.column == target { indicator = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            indicator = nil
            dragging = nil
        }
        guard let dragging, dragging != target else { return false }
        if target == .name {
            onMove(dragging, .name, true)
        } else {
            onMove(dragging, target, info.location.x < width / 2)
        }
        return true
    }

    private func update(_ info: DropInfo) {
        guard let dragging, dragging != target else { indicator = nil; return }
        let next = target == .name
            ? ColumnDropIndicator(column: .name, before: false)
            : ColumnDropIndicator(column: target, before: info.location.x < width / 2)
        if indicator != next { indicator = next }
    }
}

/// Sütun menüsü (başlık sağ tık): seçili sütunu sola/sağa taşı ya da gizle, tüm sütunları göster/gizle, varsayılana sıfırla.
struct ProcessColumnsMenu: View {
    @Binding var layout: ProcessColumnLayout
    /// Menünün açıldığı sütun.
    let column: ProcessColumn
    let contentWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if column != .name {
            Button("Sola taşı", systemImage: "arrow.left") { change { $0.moveLeft(column, width: contentWidth) } }
                .disabled(!layout.canMoveLeft(column, width: contentWidth))
            Button("Sağa taşı", systemImage: "arrow.right") { change { $0.moveRight(column, width: contentWidth) } }
                .disabled(!layout.canMoveRight(column, width: contentWidth))
            Button("“\(column.title)” sütununu gizle", systemImage: "eye.slash") { change { $0.setVisible(column, false) } }
            Divider()
        }
        Menu("Sütunlar") {
            Toggle("Ad", isOn: .constant(true)).disabled(true)
            ForEach(layout.order) { c in
                Toggle(c.title, isOn: Binding(
                    get: { layout.isVisible(c, width: contentWidth) },
                    set: { on in change { $0.setVisible(c, on) } }
                ))
            }
        }
        Button("Varsayılana sıfırla", systemImage: "arrow.counterclockwise") { change { $0.reset() } }
            .disabled(layout.isDefault)
    }

    private func change(_ edit: (inout ProcessColumnLayout) -> Void) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { edit(&layout) }
    }
}
