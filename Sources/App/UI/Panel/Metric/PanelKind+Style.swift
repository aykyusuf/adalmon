import SwiftUI

extension PanelKind {
    var tint: Color {
        switch self {
        case .cpu: .blue
        case .gpu: .purple
        case .memory: .green
        case .disk: .indigo
        case .network: .cyan
        case .temperature: .orange
        case .battery: .green
        case .combined: .accentColor
        }
    }
}
