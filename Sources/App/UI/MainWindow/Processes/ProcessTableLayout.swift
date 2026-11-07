import CoreGraphics

/// "İşlemler" tablosunun sütun genişlikleri. Sabit değil, ölçülen genişliğe göre hesaplanır (saf mantık, test edilir):
/// dar pencerede ad kısalır; genişledikçe önce ad, sonra ölçüt sütunları (en çok 1,5×), sonra ad yeniden büyür;
/// çok genişte Tür / Süreç / PID sütunları eklenir. Artan boşluk tablonun sağında kalır (Etkinlik Monitörü gibi),
/// böylece sayılar adın hemen yanında durur. Toplam hiçbir zaman verilen genişliği aşmaz.
enum ProcessTableLayout {
    static let nameMinWidth: CGFloat = 220
    static let nameIdealWidth: CGFloat = 300
    /// Dar genişlikte ad en az tablonun bu oranını alır (en çok `nameIdealWidth`'e kadar); ölçüt sütunları küçülür.
    static let nameMinShare: CGFloat = 0.32
    /// Ölçüt sütunlarının dar genişlikte inebileceği en küçük çarpan (sayılar sığmaya devam eder).
    static let minMetricScale: CGFloat = 0.8
    static let nameMaxWidth: CGFloat = 460
    /// Ad bu genişliğin altına yalnızca aşırı darlıkta iner.
    static let nameFloorWidth: CGFloat = 120
    static let maxMetricScale: CGFloat = 1.5
    static let rowHeight: CGFloat = 30
    static let headerHeight: CGFloat = 52
    /// Başlıkta sol/sağ iç boşluk: satırlar 12 pt `listRowInsets` + List'in kendi ~8 pt iç payıyla başlar; başlık aynı hizada kalsın.
    static let leadingInset: CGFloat = 20
    static let trailingInset: CGFloat = 20

    static let numericColumns: [ProcessColumn] = [.cpu, .memory, .disk, .network, .gpu, .energy]

    /// Bu içerik genişliğinden (sütunların kullanabileceği) itibaren eklenen bilgi sütunları.
    static let extraColumnThresholds: [(minWidth: CGFloat, column: ProcessColumn)] = [
        (1_150, .processCount), (1_350, .category), (1_550, .pid),
    ]

    static func baseWidth(_ column: ProcessColumn) -> CGFloat {
        switch column {
        case .name: nameMinWidth
        case .cpu: 72
        case .memory: 84
        case .disk: 92
        case .network: 92
        case .gpu: 72
        case .energy: 76
        case .category: 104
        case .processCount: 72
        case .pid: 76
        }
    }

    /// `width`: sütunlara ayrılabilen genişlik (satır iç boşlukları düşülmüş).
    static func columns(forWidth width: CGFloat) -> ProcessTableColumns {
        let w = max(0, width)
        let metrics = numericColumns + extraColumnThresholds.filter { w >= $0.minWidth }.map(\.column)
        let baseSum = metrics.reduce(0) { $0 + baseWidth($1) }
        // Adın asgari payı: tablonun ~%32'si, ama en az `nameMinWidth`, en çok `nameIdealWidth`.
        let nameFloor = min(nameIdealWidth, max(nameMinWidth, w * nameMinShare))

        var scale: CGFloat = 1
        var name = nameFloor
        if w - baseSum >= nameFloor {
            var spare = w - baseSum - nameFloor
            let nameGrow = min(spare, nameIdealWidth - nameFloor)
            name += nameGrow
            spare -= nameGrow
            let scaleGrow = min(spare, baseSum * (maxMetricScale - 1))
            scale += scaleGrow / baseSum
            spare -= scaleGrow
            name += min(spare, nameMaxWidth - name)
        } else {
            // Dar: önce ölçüt sütunları küçülür (en çok %20) ki ad `nameFloor`'u bulsun; o da yetmezse ad kalanı alır,
            // yetmezse sütunlar toplamı sığacak kadar küçülür.
            scale = max(minMetricScale, min(1, (w - nameFloor) / baseSum))
            name = w - baseSum * scale
            if name < 0 {
                scale = w / baseSum
                name = 0
            }
        }
        let entries = metrics.map { ProcessTableColumns.Entry(column: $0, width: (baseWidth($0) * scale).rounded(.down)) }
        return ProcessTableColumns(nameWidth: name.rounded(.down), entries: entries)
    }

    /// Ölçülen kap genişliğinden satır iç boşlukları düşülerek sütunlara ayrılabilen genişlik.
    static func contentWidth(forContainer width: CGFloat) -> CGFloat { width - leadingInset - trailingInset - rowSafetyMargin }

    /// Satırların kullanılabilir genişliği (kaydırıcı payı) başlıktakinden biraz dar olabilir; taşan satır ortalanıp sütunları
    /// başlığa göre kaydırırdı. Bu pay sütunların satıra her zaman sığmasını sağlar.
    static let rowSafetyMargin: CGFloat = 12
}
