import AppKit
import SwiftUI

/// Uyarı balonu ve kenar parlaması pencerelerini yalnız gösterilirken oluşturur, bitince serbest bırakır (pil).
@MainActor
final class BatteryAlertPresenter {
    static let bubbleDuration: TimeInterval = 5
    static let glowDuration: TimeInterval = 2.2

    private var bubble: NSPanel?
    /// Balon görünürken gelen uyarılar sırayla gösterilir (en çok 4 bekler); biri kapanınca sıradaki açılır.
    private var pending: [() -> Void] = []
    static let maxPending = 4
    private var bubbleTask: Task<Void, Never>?
    private var glowWindows: [NSWindow] = []
    private var glowTask: Task<Void, Never>?

    var isShowingBubble: Bool { bubble != nil }
    var pendingBubbles: Int { pending.count }
    var isShowingGlow: Bool { !glowWindows.isEmpty }

    func show(_ event: BatteryAlertEvent) {
        switch event.action.presentation {
        case .bubbleCenter: showBubble(event, top: false)
        case .bubbleTop: showBubble(event, top: true)
        case .edgeGlow: showGlow(event)
        case .none: break
        }
    }

    // MARK: Balon

    private func showBubble(_ event: BatteryAlertEvent, top: Bool) {
        showPanel(BatteryAlertBubbleView(event: event, onClose: { [weak self] in self?.dismissBubble() }),
                  contentSize: BatteryAlertBubbleView.size, top: top, duration: Self.bubbleDuration)
    }

    /// Genel uyarılar (limit, mobil veri, kural…) için aynı balon penceresi; üstte gösterilir. Düğmeli balon biraz daha uzun kalır.
    func showMessage(_ message: AlertMessage, action: InAppAlertAction?) {
        let view = InAppAlertBubbleView(message: message, action: action.map { action in
            InAppAlertAction(title: action.title) { [weak self] in action.run(); self?.dismissBubble() }
        }, onClose: { [weak self] in self?.dismissBubble() })
        let sound = message.sound
        showPanel(view, contentSize: InAppAlertBubbleView.size, top: true, duration: action == nil ? 6 : 10) {
            if sound { NSSound(named: NSSound.Name("Glass"))?.play() }
        }
    }

    private func showPanel<Content: View>(_ content: Content, contentSize: CGSize, top: Bool, duration: TimeInterval,
                                          onShow: @escaping () -> Void = {}) {
        if bubble != nil {
            if pending.count < Self.maxPending {
                pending.append { [weak self] in self?.showPanel(content, contentSize: contentSize, top: top, duration: duration, onShow: onShow) }
            }
            return
        }
        onShow()
        let size = NSSize(width: contentSize.width + 24, height: contentSize.height + 24)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: content.padding(12))
        let screen = Self.targetScreen()
        let frame = screen.visibleFrame
        let y = top ? frame.maxY - size.height - 8 : frame.midY - size.height / 2
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: y))
        panel.orderFrontRegardless()
        bubble = panel
        bubbleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismissBubble()
        }
    }

    func dismissBubble() {
        bubbleTask?.cancel()
        bubbleTask = nil
        guard let panel = bubble else { return }
        bubble = nil
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
        if !pending.isEmpty { pending.removeFirst()() }
    }

    // MARK: Kenar parlaması

    private func showGlow(_ event: BatteryAlertEvent) {
        dismissGlow()
        let color = BatteryAlertBubbleView.tint(for: event)
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .statusBar
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.contentView = NSHostingView(rootView: EdgeGlowView(color: color, duration: Self.glowDuration))
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            glowWindows.append(window)
        }
        glowTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.glowDuration + 0.2))
            guard !Task.isCancelled else { return }
            self?.dismissGlow()
        }
    }

    func dismissGlow() {
        glowTask?.cancel()
        glowTask = nil
        for w in glowWindows {
            w.orderOut(nil)
            w.contentView = nil
            w.close()
        }
        glowWindows = []
    }

    private static func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

struct BatteryAlertBubbleView: View {
    static let size = CGSize(width: 420, height: 88)

    let event: BatteryAlertEvent
    var onClose: () -> Void = {}
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Uyarı rengi: düşük pil turuncu (≤%10 kırmızı), şarj/dolu yeşil, fişe takıldı nane, fişten çekildi mavi. Canlı ama göz yormayan tonlar.
    static func tint(for event: BatteryAlertEvent) -> Color {
        switch event.kind {
        case .low(let t): t <= 10 ? Color(red: 1.0, green: 0.31, blue: 0.27) : Color(red: 1.0, green: 0.62, blue: 0.10)
        case .charged: Color(red: 0.24, green: 0.84, blue: 0.40)
        case .pluggedIn: Color(red: 0.22, green: 0.86, blue: 0.62)
        case .unplugged: Color(red: 0.25, green: 0.60, blue: 1.0)
        }
    }

    private var symbol: String {
        switch event.kind {
        case .low: event.level <= 10 ? "battery.0percent" : "battery.25percent"
        case .charged: "battery.100percent.bolt"
        case .pluggedIn: "bolt.fill"
        case .unplugged: "powerplug.portrait"
        }
    }

    var body: some View {
        let tint = Self.tint(for: event)
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(tint.opacity(0.22), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: shown ? CGFloat(event.level) / 100 : 0)
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                Text(event.message)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.82))   // gri değil: koyu zeminde net okunur
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.78))
                    .frame(width: 32, height: 32)
                    .background(.primary.opacity(0.14), in: .circle)
            }
            .buttonStyle(.plain)
            .help("Kapat")
            .accessibilityLabel("Kapat")
        }
        .padding(.horizontal, 18)
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            ZStack {
                Capsule().fill(.regularMaterial)
                // Uyarı rengiyle soldan sağa solan hafif ton: kartı ayırt edilir kılar, yazıyı boğmaz.
                Capsule().fill(LinearGradient(colors: [tint.opacity(0.26), tint.opacity(0.08)], startPoint: .leading, endPoint: .trailing))
            }
        }
        .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1))
        .shadow(color: tint.opacity(0.25), radius: 14, y: 4)
        .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
        .scaleEffect(shown || reduceMotion ? 1 : 0.92)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.25)) { shown = true } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title). \(event.message)")
    }
}

/// Genel uyarı balonu (NOTIF-01): simge, başlık, iki satıra kadar metin, isteğe bağlı eylem düğmesi.
struct InAppAlertBubbleView: View {
    static let size = CGSize(width: 460, height: 96)
    static let tint = Color(red: 1.0, green: 0.62, blue: 0.10)

    let message: AlertMessage
    let action: InAppAlertAction?
    var onClose: () -> Void = {}
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tint = Self.tint
        HStack(spacing: 14) {
            Image(systemName: message.symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.18), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(message.body)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.82))
                    .lineLimit(2)
            }
            .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            if let action {
                Button(action.title) { action.run() }
                    .controlSize(.small)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.78))
                    .frame(width: 28, height: 28)
                    .background(.primary.opacity(0.14), in: .circle)
            }
            .buttonStyle(.plain)
            .help("Kapat")
            .accessibilityLabel("Kapat")
        }
        .padding(.horizontal, 16)
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.20), tint.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(tint.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
        .scaleEffect(shown || reduceMotion ? 1 : 0.94)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.2)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(message.title). \(message.body)")
    }
}

/// Ekranın kenarında yumuşak renkli parlama; ~2 sn. Hareketi azalt açıkken tek yavaş solma.
struct EdgeGlowView: View {
    let color: Color
    var duration: TimeInterval = 2.2
    @State private var opacity = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let t = max(90, min(geo.size.width, geo.size.height) * 0.16)
            let strong = color.opacity(0.9), soft = color.opacity(0.28)
            ZStack {
                LinearGradient(stops: [.init(color: strong, location: 0), .init(color: soft, location: 0.35), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: t).frame(maxHeight: .infinity, alignment: .top)
                LinearGradient(stops: [.init(color: strong, location: 0), .init(color: soft, location: 0.35), .init(color: .clear, location: 1)],
                               startPoint: .bottom, endPoint: .top)
                    .frame(height: t).frame(maxHeight: .infinity, alignment: .bottom)
                LinearGradient(stops: [.init(color: strong, location: 0), .init(color: soft, location: 0.35), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: t).frame(maxWidth: .infinity, alignment: .leading)
                LinearGradient(stops: [.init(color: strong, location: 0), .init(color: soft, location: 0.35), .init(color: .clear, location: 1)],
                               startPoint: .trailing, endPoint: .leading)
                    .frame(width: t).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .task {
            if reduceMotion {
                withAnimation(.easeInOut(duration: duration * 0.4)) { opacity = 0.55 }
                try? await Task.sleep(for: .seconds(duration * 0.4))
                withAnimation(.easeInOut(duration: duration * 0.6)) { opacity = 0 }
                return
            }
            withAnimation(.easeOut(duration: 0.35)) { opacity = 1 }
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(.easeInOut(duration: 0.5)) { opacity = 0.45 }
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.easeOut(duration: 0.3)) { opacity = 1 }
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeIn(duration: duration - 1.15)) { opacity = 0 }
        }
        .accessibilityHidden(true)
    }
}
