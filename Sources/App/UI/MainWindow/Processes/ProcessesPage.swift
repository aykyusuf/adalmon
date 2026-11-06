import SwiftUI

/// Süreçler sayfası: Şu an (canlı) | Geçmiş | Disk.
struct ProcessesPage: View {
    let model: AppModel
    @State private var tab: Tab = .live

    enum Tab: String, CaseIterable, Identifiable {
        case live = "Şu an", history = "Geçmiş", disk = "Disk"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: MainSection.processes.title) {
                Picker("Görünüm", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 270)
            }
            switch tab {
            case .live: ProcessLiveView(model: model)
            case .history: ProcessHistoryView(store: model.store)
            case .disk: ProcessDiskView(model: model)
            }
        }
        .padding(24)
    }
}
