import Foundation

/// Which network quantity the "Ağ" card shows.
enum NetworkCardSource: String, CaseIterable, Identifiable, Sendable {
    case speed, lastMinute, today

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .speed: "Anlık"
        case .lastMinute: "Son 1 dk"
        case .today: "Bugün"
        }
    }

    var download: DataField {
        switch self {
        case .speed: .download
        case .lastMinute: .downloadLast60
        case .today: .downloadToday
        }
    }

    var upload: DataField {
        switch self {
        case .speed: .upload
        case .lastMinute: .uploadLast60
        case .today: .uploadToday
        }
    }

    /// Maps any network field to its source and its instant-speed counterpart (the card's canonical field).
    static func split(_ field: DataField) -> (source: NetworkCardSource, canonical: DataField)? {
        for source in allCases {
            if field == source.download { return (source, .download) }
            if field == source.upload { return (source, .upload) }
        }
        return nil
    }

    func resolve(_ canonical: DataField) -> DataField {
        switch canonical {
        case .download: download
        case .upload: upload
        default: canonical
        }
    }
}
