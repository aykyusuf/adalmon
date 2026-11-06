import SwiftUI

/// KB/s cinsinden hız girişi (doğrudan KB/s bağlaması); boş = sınırsız.
struct KilobyteField: View {
    let title: String
    @Binding var kilobytes: Double?

    init(_ title: String, kilobytes: Binding<Double?>) {
        self.title = title
        _kilobytes = kilobytes
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: $kilobytes, format: .number.precision(.fractionLength(0...1)), prompt: Text("Sınırsız"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text("KB/s").foregroundStyle(.secondary)
            }
        }
    }
}
