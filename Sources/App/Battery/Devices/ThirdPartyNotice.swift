import Foundation

/// Uygulamayla birlikte dağıtılan üçüncü taraf kitaplıkların lisans bildirimi (Ayarlar › Genel › Lisanslar, README).
struct ThirdPartyNotice: Identifiable, Equatable, Sendable {
    var name: String
    var version: String
    var license: String
    var url: URL

    var id: String { name }

    static let all: [ThirdPartyNotice] = [
        ThirdPartyNotice(name: "libimobiledevice", version: "1.0.6", license: "LGPL-2.1-or-later", url: URL(string: "https://github.com/libimobiledevice/libimobiledevice")!),
        ThirdPartyNotice(name: "libimobiledevice-glue", version: "1.0.0", license: "LGPL-2.1-or-later", url: URL(string: "https://github.com/libimobiledevice/libimobiledevice-glue")!),
        ThirdPartyNotice(name: "libplist", version: "2.0.12", license: "LGPL-2.1-or-later", url: URL(string: "https://github.com/libimobiledevice/libplist")!),
        ThirdPartyNotice(name: "libusbmuxd", version: "2.0.7", license: "LGPL-2.1-or-later", url: URL(string: "https://github.com/libimobiledevice/libusbmuxd")!),
        ThirdPartyNotice(name: "Simple Icons (Claude ve OpenAI logo yolları)", version: "15.0.0", license: "CC0-1.0", url: URL(string: "https://github.com/simple-icons/simple-icons")!),
        ThirdPartyNotice(name: "OpenSSL (libssl, libcrypto)", version: "4.x", license: "Apache-2.0", url: URL(string: "https://github.com/openssl/openssl")!),
    ]

    static let lgplStatement = """
    Adalmon, iPhone ve iPad pil ayrıntılarını okumak için yukarıdaki kitaplıkları dinamik olarak (dlopen) kullanır. \
    Kitaplıklar değiştirilmeden Adalmon.app/Contents/Frameworks içinde bulunur; kaynak kodları bağlantılardaki depolardadır. \
    LGPL gereği kitaplıkları değiştirilmiş sürümleriyle değiştirebilirsin (uygulamayı yeniden imzalaman gerekir). \
    Bu özellik kapalıyken ya da kitaplıklar bulunamazsa Adalmon geri kalan işlevleriyle çalışır.
    """

    static let trademarkStatement = """
    Limitler sayfasındaki Claude ve OpenAI logoları Anthropic ve OpenAI'nin ticari markalarıdır; yalnızca ilgili hizmeti tanıtmak için \
    kullanılır, bir ortaklık ya da onay anlamına gelmez. Logo yolları Simple Icons projesinden (CC0-1.0, kamu malı) alınmıştır.
    """
}
