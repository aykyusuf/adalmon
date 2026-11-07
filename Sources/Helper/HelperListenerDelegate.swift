import Foundation

/// Bağlantıyı yalnızca imzası `HelperConstants.clientRequirement` ile eşleşen istemciye açar.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let service: HelperXPCService

    init(service: HelperXPCService) { self.service = service }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.setCodeSigningRequirement(HelperConstants.clientRequirement)
        newConnection.exportedInterface = NSXPCInterface(with: AdalmonHelperProtocol.self)
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}
