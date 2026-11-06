import SwiftUI

/// Hazır değerler + "Sınırsız" + özel değer (KB/s) menüsü.
struct InspectorRatePicker: View {
    let symbol: String
    let label: String
    let value: Int?
    let onChange: (Int?) -> Void

    @State private var showCustom = false
    @State private var customKB = ""

    var body: some View {
        HStack {
            Label(label, systemImage: symbol)
            Spacer(minLength: 8)
            Menu {
                item("Sınırsız", selected: value == nil) { onChange(nil) }
                Divider()
                ForEach(ThrottlePreset.values, id: \.self) { v in
                    item(AppModel.rateText(v), selected: value == v) { onChange(v) }
                }
                if let value, !ThrottlePreset.values.contains(value) {
                    item(AppModel.rateText(value), selected: true) {}
                }
                Divider()
                Button("Özel…") {
                    customKB = value.map { String($0 / 1024) } ?? ""
                    showCustom = true
                }
            } label: {
                Text(value.map(AppModel.rateText) ?? "Sınırsız")
                    .font(.callout)
                    .monospacedDigit()
            }
            .menuStyle(.button)
            .fixedSize()
            .accessibilityLabel("\(label) sınırı")
            .popover(isPresented: $showCustom, arrowEdge: .bottom) {
                HStack {
                    TextField("KB/s", text: $customKB)
                        .frame(width: 80)
                        .onSubmit(applyCustom)
                    Text("KB/s")
                    Button("Uygula", action: applyCustom)
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func item(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func applyCustom() {
        let kb = Int(customKB.trimmingCharacters(in: .whitespaces)) ?? 0
        onChange(kb > 0 ? kb * 1024 : nil)
        showCustom = false
    }
}
