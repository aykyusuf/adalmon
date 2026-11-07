import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

/// IOPS olayı: sınır açıkken pil yüzdesi/fiş değişince hemen değerlendir (zamanlayıcıyı beklemeden).
nonisolated(unsafe) private var powerEventHandler: (@Sendable () -> Void)?

/// Uyku/uyanma: kök etki alanı bağlantı noktası (IOAllowPowerChange için gerekli).
nonisolated(unsafe) private var rootDomainPort: io_connect_t = 0

// iokit_common_msg(0x270/0x280/0x300) değerleri (Swift makroyu içe aktarmaz).
private let messageCanSystemSleep: UInt32 = 0xE000_0270
private let messageSystemWillSleep: UInt32 = 0xE000_0280
private let messageSystemHasPoweredOn: UInt32 = 0xE000_0300

private func systemPowerCallback(_ refcon: UnsafeMutableRawPointer?, _ service: io_service_t, _ messageType: UInt32,
                                 _ argument: UnsafeMutableRawPointer?) {
    switch messageType {
    case messageCanSystemSleep, messageSystemWillSleep:
        // Onay verilmezse uyku ~30 sn gecikir. Şarj engeli uykuda SMC'de kalır; sınır korunur.
        IOAllowPowerChange(rootDomainPort, Int(bitPattern: argument))
    case messageSystemHasPoweredOn:
        powerEventHandler?() // uyanınca bir sonraki yoklamayı beklemeden değerlendir
    default:
        break
    }
}

/// Yardımcının yaşam döngüsü: çekirdek, XPC dinleyici, IOPS olayı, SIGTERM/SIGINT ile güvenli çıkış.
@MainActor
final class HelperRunner {
    private let core: HelperCore
    private let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
    private let delegate: HelperListenerDelegate
    private var signalSources: [DispatchSourceSignal] = []
    private var powerSource: CFRunLoopSource?
    private var sleepNotifyPort: IONotificationPortRef?
    private var sleepNotifier: io_object_t = 0

    init() {
        let holder = TimerHolder()
        let core = HelperCore(smc: SMCDevice(), battery: IOPSBatteryProvider(), power: PmsetRunner(),
                              store: FileStateStore(), scheduler: holder)
        holder.install(PollTimer { Task { await core.tickIfNeeded() } })
        self.core = core
        self.delegate = HelperListenerDelegate(service: HelperXPCService(core: core))
    }

    func start() {
        let core = core
        let listener = listener
        listener.delegate = delegate
        // Dinleyici çekirdek hazır olunca açılır: erken gelen komut "desteklenmiyor" diye yanlış yanıtlanmasın.
        Task {
            await core.start()
            listener.resume()
        }

        powerEventHandler = { Task { await core.tickIfNeeded() } }
        if let src = IOPSNotificationCreateRunLoopSource({ _ in powerEventHandler?() }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            powerSource = src
        }

        rootDomainPort = IORegisterForSystemPower(nil, &sleepNotifyPort, systemPowerCallback, &sleepNotifier)
        if rootDomainPort != 0, let port = sleepNotifyPort,
           let src = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }

        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                Task {
                    await core.shutdown()
                    exit(0)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}

/// `HelperCore` ile `PollTimer` karşılıklı bağımlı olduğu için zamanlayıcı sonradan takılır.
private final class TimerHolder: PollScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var timer: PollTimer?

    func install(_ timer: PollTimer) { lock.lock(); self.timer = timer; lock.unlock() }

    func setPolling(_ active: Bool) {
        lock.lock(); let t = timer; lock.unlock()
        t?.setPolling(active)
    }
}
