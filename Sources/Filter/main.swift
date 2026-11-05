import Foundation
import NetworkExtension

autoreleasepool {
    NEProvider.startSystemExtensionMode()
    XPCServer.shared.start()
}
dispatchMain()
