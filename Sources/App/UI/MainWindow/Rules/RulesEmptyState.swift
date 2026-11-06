import SwiftUI

struct RulesEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Henüz kural yok", systemImage: "shield.lefthalf.filled")
        } description: {
            Text("Örneğin: Safari son 10 dakikada 500 MB'ı aşarsa hızını 256 KB/s'ye düşür.")
        } actions: {
            Button("Kural ekle", systemImage: "plus", action: onAdd)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }
}
