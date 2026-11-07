import CoreGraphics

/// Bir genişlik için hesaplanmış sütun yerleşimi: başlık ve satırlar aynı değerleri kullanır, böylece hizalı kalır.
struct ProcessTableColumns: Equatable {
    struct Entry: Equatable, Identifiable {
        var column: ProcessColumn
        var width: CGFloat
        var id: ProcessColumn { column }
    }

    var nameWidth: CGFloat
    /// Ad dışındaki sütunlar, soldan sağa.
    var entries: [Entry]

    /// Toplam genişlik (ad dahil); sütunların sağındaki boşluk hariç.
    var totalWidth: CGFloat { nameWidth + entries.reduce(0) { $0 + $1.width } }
}
