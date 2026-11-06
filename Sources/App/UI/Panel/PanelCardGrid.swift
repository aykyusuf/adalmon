import SwiftUI

/// Sistem kartları: 3 sütunlu ızgara. Kartlar tıklanınca (Dock modunda) ana pencere açılır.
struct PanelCardGrid: View {
    static let columns = 3

    let data: PanelData
    let cards: [PanelCardKind]
    let onOpen: () -> Void

    var body: some View {
        let rows = stride(from: 0, to: cards.count, by: Self.columns).map { Array(cards[$0..<min($0 + Self.columns, cards.count)]) }
        let metrics = SystemMetric.all(data, showTemperatures: false)
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row) { kind in
                        cell(PanelCardModel.make(kind, data, metrics: metrics))
                    }
                    ForEach(0..<(Self.columns - row.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ card: PanelCardModel) -> some View {
        if data.opensMainWindow {
            Button(action: onOpen) { PanelMetricCard(card: card) }
                .buttonStyle(.plain)
                .accessibilityHint("Adalmon penceresini açar")
        } else {
            PanelMetricCard(card: card)
        }
    }
}
