import SwiftUI

/// KB/s cinsinden hız girişi; boş = sınırsız. Dışarıya byte/sn olarak yazar.
struct RateField: View {
    let title: String
    @Binding var bytesPerSec: Int?
    @State private var kilobytes: Double?

    init(_ title: String, bytesPerSec: Binding<Int?>) {
        self.title = title
        _bytesPerSec = bytesPerSec
        _kilobytes = State(initialValue: bytesPerSec.wrappedValue.map { Double($0) / RuleDraft.bytesPerKB })
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer()
            TextField(title, value: $kilobytes, format: .number.precision(.fractionLength(0...1)), prompt: Text("Sınırsız"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text("KB/s").foregroundStyle(.secondary)
        }
        .onChange(of: kilobytes) {
            let value = (kilobytes ?? 0) > 0 ? Int((kilobytes ?? 0) * RuleDraft.bytesPerKB) : nil
            if value != bytesPerSec { bytesPerSec = value }
        }
    }
}
