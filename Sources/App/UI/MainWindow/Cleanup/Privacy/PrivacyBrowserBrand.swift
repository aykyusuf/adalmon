import SwiftUI

extension PrivacyBrowser {
    /// Tarayıcıya özgü marka vurgusu (kart ikonları, onay kutuları, başlık logosu).
    var brandAccent: CleanupAccent {
        switch self {
        case .chrome: CleanupAccent(hue: 0.01, saturation: 0.74, brightness: 0.93)
        case .edge: CleanupAccent(hue: 0.48, saturation: 0.82, brightness: 0.74)
        case .safari: CleanupAccent(hue: 0.58, saturation: 0.78, brightness: 0.98)
        }
    }
}

/// Basit marka logoları (kendi çizimimiz): Chrome üç dilimli halka, Edge dalga renkli "e", Safari pusula.
struct PrivacyBrowserLogo: View {
    let browser: PrivacyBrowser
    var size: CGFloat = 30

    var body: some View {
        Group {
            switch browser {
            case .chrome: chrome
            case .edge: edge
            case .safari: safari
            }
        }
        .frame(width: size, height: size)
        .shadow(color: browser.brandAccent.deep.opacity(0.35), radius: size * 0.1, y: size * 0.06)
        .accessibilityHidden(true)
    }

    private var chrome: some View {
        ZStack {
            PieSlice(from: 210, to: 330).fill(Color(red: 0.92, green: 0.26, blue: 0.21))
            PieSlice(from: 330, to: 450).fill(Color(red: 0.98, green: 0.74, blue: 0.02))
            PieSlice(from: 90, to: 210).fill(Color(red: 0.20, green: 0.66, blue: 0.33))
            Circle().fill(.white).frame(width: size * 0.5, height: size * 0.5)
            Circle().fill(Color(red: 0.26, green: 0.52, blue: 0.96)).frame(width: size * 0.38, height: size * 0.38)
        }
    }

    private var edge: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.16, green: 0.62, blue: 0.93), Color(red: 0.13, green: 0.76, blue: 0.52)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
            Text("e").font(.system(size: size * 0.66, weight: .heavy, design: .rounded)).foregroundStyle(.white).offset(y: -size * 0.03)
        }
    }

    private var safari: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.45, green: 0.85, blue: 1.0), Color(red: 0.07, green: 0.45, blue: 0.98)],
                                         startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1)
            Image(systemName: "safari.fill").font(.system(size: size * 0.74)).symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color(red: 0.07, green: 0.45, blue: 0.98))
        }
    }
}

/// Merkezden dilim; açılar derece, saat yönünde, doğudan başlar.
private struct PieSlice: Shape {
    let from: Double
    let to: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center, radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
        path.closeSubpath()
        return path
    }
}
