import CoreGraphics

/// "İşlemler" tablosunun sütun genişlikleri: başlık ve satırlar aynı değerleri kullanır, böylece hizalı kalır.
enum ProcessTableLayout {
    static let nameMinWidth: CGFloat = 190
    static let rowHeight: CGFloat = 30
    static let headerHeight: CGFloat = 52

    static func width(_ column: ProcessColumn) -> CGFloat {
        switch column {
        case .name: nameMinWidth
        case .cpu: 72
        case .memory: 84
        case .disk: 92
        case .network: 92
        case .gpu: 72
        case .energy: 76
        }
    }

    static let numericColumns: [ProcessColumn] = [.cpu, .memory, .disk, .network, .gpu, .energy]
}
