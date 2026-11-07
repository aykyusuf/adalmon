import SwiftUI

/// "Hız sınırı koy…": indirme / yükleme için hazır değerler (mevcut `AppModel.setLimit`).
struct ProcessLimitSheet: View {
    let row: LiveRow
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var down: Int
    @State private var up: Int
    @State private var onlyMobile: Bool

    /// 0 = sınır yok (byte/sn).
    static let presets: [(title: String, value: Int)] = [
        ("Sınırsız", 0), ("64 KB/s", 64 * 1024), ("256 KB/s", 256 * 1024), ("1 MB/s", 1_048_576),
        ("5 MB/s", 5 * 1_048_576), ("20 MB/s", 20 * 1_048_576),
    ]

    init(row: LiveRow, model: AppModel) {
        self.row = row
        self.model = model
        let current = model.limit(for: row.key)
        _down = State(initialValue: current?.downBytesPerSec ?? 0)
        _up = State(initialValue: current?.upBytesPerSec ?? 0)
        _onlyMobile = State(initialValue: current?.onlyOnMobile ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("“\(row.name)” için hız sınırı").font(.title3.weight(.semibold))
            Form {
                Picker("İndirme", selection: $down) { ForEach(Self.presets, id: \.value) { Text($0.title).tag($0.value) } }
                Picker("Yükleme", selection: $up) { ForEach(Self.presets, id: \.value) { Text($0.title).tag($0.value) } }
                Toggle("Yalnızca mobil veride", isOn: $onlyMobile)
            }
            .formStyle(.grouped)
            if model.installer.state != .active {
                Label("Ağ filtresi kurulu değil; sınır filtre kurulunca geçerli olur.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if model.limit(for: row.key) != nil {
                    Button("Sınırı kaldır", role: .destructive) { model.setLimit(row.key, nil); dismiss() }
                }
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }
                Button("Uygula") {
                    model.setLimit(row.key, AppLimit(downBytesPerSec: down > 0 ? down : nil, upBytesPerSec: up > 0 ? up : nil, onlyOnMobile: onlyMobile))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(down == 0 && up == 0)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
