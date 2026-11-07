import AppKit
import SwiftUI

/// Uyarı balonu ve kenar parlaması pencerelerini yalnız gösterilirken oluşturur, bitince serbest bırakır (pil).
@MainActor
final class BatteryAlertPresenter {
    static let bubbleDuration: TimeInterval = 5
    static let glowDuration: TimeInterval = 2.2

    private var bubble: NSPanel?
    private var bubbleTask: Task<Void, Never>?
    private var glowWindows: [NSWindow] = []
    private var glowTask: Task<Void, Never>?

    var isShowingBubble: Bool { bubble != nil }
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
        dismissBubble()
        let size = NSSize(width: BatteryAlertBubbleView.size.width + 24, height: BatteryAlertBubbleView.size.height + 24)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: BatteryAlertBubbleView(event: event, onClose: { [weak self] in self?.dismissBubble() })
            .padding(12))
        let screen = Self.targetScreen()
        let frame = screen.visibleFrame
        let y = top ? frame.maxY - size.height - 8 : frame.midY - size.height / 2
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: y))
        panel.orderFrontRegardless()
        bubble = panel
        bubbleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.bubbleDuration))
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
    static let size = CGSize(width: 330, height: 64)

    let event: BatteryAlertEvent
    var onClose: () -> Void = {}
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func tint(for event: BatteryAlertEvent) -> Color {
        switch event.kind {
        case .low(let t): t <= 10 ? .red : .orange
        case .charged: .green
        case .pluggedIn: .green
        case .unplugged: .blue
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
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(.primary.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: shown ? CGFloat(event.level) / 100 : 0)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(.subheadline, weight: .semibold))
                Text(event.message).font(.system(.callout, design: .rounded)).foregroundStyle(.secondary).monospacedDigit()
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.quaternary, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kapat")
        }
        .padding(.horizontal, 12)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .scaleEffect(shown || reduceMotion ? 1 : 0.92)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.25)) { shown = true } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title). \(event.message)")
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
