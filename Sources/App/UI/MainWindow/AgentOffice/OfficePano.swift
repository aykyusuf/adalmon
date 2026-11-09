import AppKit
import Foundation
import IOKit.pwr_mgt
import Observation
import SwiftUI

/// Ofis penceresi "Pano görünümü" (kiosk): Otomatik (tam ekranda açık), Hep, Kapalı.
enum OfficePanoMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, always, off

    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Otomatik"
        case .always: "Hep"
        case .off: "Kapalı"
        }
    }

    /// Pano düzeni (kenar boşluğu, eşit aralık, büyük etiketler, köşe katmanı) etkin mi?
    func isActive(fullScreen: Bool) -> Bool {
        switch self {
        case .auto: fullScreen
        case .always: true
        case .off: false
        }
    }
}

/// Tam ekranda araç şeridi/imleç otomatik gizleme kararı. Saf: son hareket zamanı → görünür/gizli.
enum OfficeChromeVisibility {
    static let hideDelay: TimeInterval = 3
    static let fadeDuration: TimeInterval = 0.25
    /// İmleç bu yükseklikteki üst bantta ise (görünüm noktası) şerit görünür kalır.
    static let topEdgeBand: Double = 6

    /// Şerit görünür mü? Tam ekran değilse hep; tam ekranda: imleç üst kenar/şerit üzerindeyse ya da son hareketten `hideDelay` dolmadıysa.
    static func stripVisible(fullScreen: Bool, now: Date, lastActivity: Date, pointerOnStrip: Bool) -> Bool {
        guard fullScreen else { return true }
        return pointerOnStrip || now.timeIntervalSince(lastActivity) < hideDelay
    }

    /// İmleç gizli mi? Tam ekranda şerit gizliyken ve hareketsizlik `hideDelay`'i aştıysa.
    static func cursorHidden(fullScreen: Bool, now: Date, lastActivity: Date, pointerOnStrip: Bool) -> Bool {
        fullScreen && !stripVisible(fullScreen: fullScreen, now: now, lastActivity: lastActivity, pointerOnStrip: pointerOnStrip)
    }

    /// Görünür durumun ne zaman gizliye döneceği (tek seferlik zamanlayıcı için); zaten gizliyse nil.
    static func nextHide(fullScreen: Bool, now: Date, lastActivity: Date) -> Date? {
        guard fullScreen else { return nil }
        let at = lastActivity.addingTimeInterval(hideDelay)
        return at > now ? at : nil
    }
}

/// Ekran koruma (burn-in): köşe katmanlarının konumu her 5 dakikada 8 px'e kadar kayar (4 konumlu döngü).
enum OfficePanoBurnIn {
    static let stepSeconds: TimeInterval = 300
    static let maxShift: Double = 8
    private static let cycle: [(Double, Double)] = [(0, 0), (1, 0), (1, 1), (0, 1)]

    /// (dx, dy) ∈ [0, maxShift]; dx içe doğru (kenardan uzaklaşan), dy aşağı doğru.
    static func offset(at date: Date) -> CGSize {
        let step = Int((date.timeIntervalSinceReferenceDate / stepSeconds).rounded(.down))
        let p = cycle[((step % cycle.count) + cycle.count) % cycle.count]
        return CGSize(width: p.0 * maxShift, height: p.1 * maxShift)
    }
}

/// Köşe katmanı metinleri.
enum OfficePanoText {
    /// "HH:mm" (24 saat, verilen saat dilimi).
    static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Kısa gün adı + gün + ay (ör. "Pzt 9 Kas").
    static func day(_ date: Date, timeZone: TimeZone = .current, locale: Locale = Locale(identifier: "tr_TR")) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: Calendar(identifier: .gregorian), timeZone: timeZone)
        style = style.weekday(.abbreviated).day().month(.abbreviated)
        return date.formatted(style)
    }

    /// "N oturum · M ajan · K çalışıyor" (N: oturum, M: tüm ajanlar (alt ajanlar dahil), K: çalışan).
    static func summary(members: [OfficeMember]) -> String {
        let sessions = members.filter { $0.parentID == nil }.count
        let working = members.filter { $0.status.isWorking }.count
        return "\(sessions) oturum · \(members.count) ajan · \(working) çalışıyor"
    }
}

/// Dakikada bir güncellenen saat: tek tek-atımlık Timer (dakika sınırına kurulur, tolerans 1 sn); yalnızca `start`/`stop` arasında vardır.
@MainActor @Observable
final class OfficePanoClock {
    private(set) var now = Date()
    @ObservationIgnored private var timer: Timer?
    var isRunning: Bool { timer != nil }

    static func nextMinute(after date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: ((date.timeIntervalSinceReferenceDate / 60).rounded(.down) + 1) * 60)
    }

    func start() {
        guard timer == nil else { return }
        now = Date()
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func schedule() {
        let t = Timer(fire: Self.nextMinute(after: Date()), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.timer != nil else { return }
                self.now = Date()
                self.schedule()
            }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

// MARK: Ekranı uyanık tut

/// Ekranın uykuya dalmasını engelleyen assertion'ın soyutlaması (testte sahtesi kullanılır; gerçek assertion oluşturulmaz).
@MainActor
protocol DisplaySleepAsserting: AnyObject {
    /// Assertion oluşturur; başarılıysa true. Zaten tutuluyorsa true.
    func acquire(reason: String) -> Bool
    func release()
    var isHeld: Bool { get }
}

@MainActor
final class IOKitDisplaySleepAssertion: DisplaySleepAsserting {
    private var id = IOPMAssertionID(0)
    private(set) var isHeld = false

    func acquire(reason: String) -> Bool {
        if isHeld { return true }
        var newID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason as CFString, &newID)
        guard result == kIOReturnSuccess else { return false }
        id = newID
        isHeld = true
        return true
    }

    func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(id)
        id = IOPMAssertionID(0)
        isHeld = false
    }

    isolated deinit { if isHeld { IOPMAssertionRelease(id) } }
}

/// "Ekranı uyanık tut" yaşam döngüsü: yalnızca (ayar açık VE tam ekran VE pencere açık) iken assertion tutulur; aksi halde bırakılır.
@MainActor
final class OfficeKeepAwake {
    static let reason = "Adalmon Ajan ofisi panosu"
    private let assertion: any DisplaySleepAsserting

    init(assertion: any DisplaySleepAsserting) { self.assertion = assertion }

    static func shouldHold(setting: Bool, fullScreen: Bool, windowOpen: Bool) -> Bool { setting && fullScreen && windowOpen }

    var isHolding: Bool { assertion.isHeld }

    func update(setting: Bool, fullScreen: Bool, windowOpen: Bool) {
        if Self.shouldHold(setting: setting, fullScreen: fullScreen, windowOpen: windowOpen) {
            _ = assertion.acquire(reason: Self.reason)
        } else {
            assertion.release()
        }
    }

    func releaseAll() { assertion.release() }
}

// MARK: Köşe katmanı

/// Pano köşeleri: sol üstte "N oturum · M ajan · K çalışıyor", sağ üstte saat + gün/tarih. Yarı saydam, küçük, düşük kontrast;
/// konum her 5 dakikada kayar (burn-in).
struct OfficePanoCorners: View {
    let members: [OfficeMember]
    let now: Date
    let night: Bool
    var showsClock = true

    var body: some View {
        GeometryReader { geo in
            let s = OfficePanoLayout.uiScale(viewHeight: geo.size.height)
            let shift = OfficePanoBurnIn.offset(at: now)
            let edge = 18 * s
            ZStack(alignment: .topLeading) {
                Text(OfficePanoText.summary(members: members))
                    .font(.system(size: 12.5 * s, weight: .medium))
                    .modifier(PanoPill(night: night, scale: s))
                    .padding(.leading, edge + shift.width).padding(.top, edge + shift.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if showsClock {
                    HStack(spacing: 8 * s) {
                        Text(OfficePanoText.time(now)).font(.system(size: 15 * s, weight: .semibold).monospacedDigit())
                        Text(OfficePanoText.day(now)).font(.system(size: 12.5 * s, weight: .medium)).opacity(0.8)
                    }
                    .modifier(PanoPill(night: night, scale: s))
                    .padding(.trailing, edge + shift.width).padding(.top, edge + shift.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(OfficePanoText.time(now)), \(OfficePanoText.summary(members: members))")
    }
}

private struct PanoPill: ViewModifier {
    let night: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .foregroundStyle(night ? Color.white.opacity(0.72) : Color(red: 0.25, green: 0.18, blue: 0.08).opacity(0.72))
            .padding(.horizontal, 12 * scale).padding(.vertical, 6 * scale)
            .background(Capsule().fill(night ? Color.white.opacity(0.08) : Color.white.opacity(0.42)))
            .overlay(Capsule().strokeBorder(night ? Color.white.opacity(0.10) : Color(red: 0.4, green: 0.3, blue: 0.15).opacity(0.14), lineWidth: 1))
    }
}
