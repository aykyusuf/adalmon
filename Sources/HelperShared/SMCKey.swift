import Foundation

/// Yardımcının dokunabildiği SMC anahtarlarının TAM listesi. Başka anahtar türü olarak ifade edilemez.
enum SMCKey: String, CaseIterable, Sendable, Hashable {
    case chte = "CHTE"
    case ch0b = "CH0B"
    case ch0c = "CH0C"
    case aclc = "ACLC"
}

struct SMCKeyDescriptor: Equatable, Sendable {
    var size: Int
    var dataType: String
}

/// Tek bir izinli SMC yazımı. Yalnızca `SMCWriteAllowlist` üretir; cihaz katmanı yine de `permits` ile denetler.
struct SMCWrite: Equatable, Sendable {
    let key: SMCKey
    let bytes: [UInt8]
}
