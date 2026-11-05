import Foundation

/// Ham host'u okunur bir gruba indirger: googlevideo/ytimg → YouTube, CDN alt alan adları → kayıtlı alan adı.
enum DomainGrouper {
    private static let services: [(String, [String])] = [
        ("YouTube", ["googlevideo.com", "youtube.com", "ytimg.com", "ggpht.com", "youtubei.googleapis.com", "youtu.be"]),
        ("Netflix", ["netflix.com", "nflxvideo.net", "nflximg.net", "nflxso.net"]),
        ("Instagram", ["instagram.com", "cdninstagram.com"]),
        ("WhatsApp", ["whatsapp.net", "whatsapp.com"]),
        ("Discord", ["discord.com", "discord.gg", "discordapp.com", "discordapp.net", "discord.media"]),
        ("iCloud", ["icloud.com", "icloud-content.com", "apple-cloudkit.com"]),
        ("Apple", ["apple.com", "aaplimg.com", "mzstatic.com", "cdn-apple.com"]),
        ("Spotify", ["spotify.com", "scdn.co", "spotifycdn.com"]),
        ("Twitch", ["twitch.tv", "ttvnw.net", "jtvnw.net"]),
        ("X", ["twitter.com", "x.com", "twimg.com"]),
        ("Claude", ["anthropic.com", "claude.ai", "claudeusercontent.com"]),
        ("Google", ["google.com", "gstatic.com", "googleapis.com", "googleusercontent.com", "gvt1.com"]),
        ("Steam", ["steampowered.com", "steamcontent.com", "steamstatic.com"]),
    ]

    private static let twoLevelTLDs: Set<String> = ["com.tr", "net.tr", "org.tr", "gov.tr", "edu.tr", "co.uk", "com.au", "co.jp"]

    static func group(_ host: String) -> String {
        let h = host.lowercased()
        if h.isEmpty || h == "?" { return "Bilinmeyen" }
        if isIP(h) { return h }
        for (name, suffixes) in services where suffixes.contains(where: { h == $0 || h.hasSuffix("." + $0) }) {
            return name
        }
        return registrable(h)
    }

    static func registrable(_ h: String) -> String {
        let parts = h.split(separator: ".")
        guard parts.count > 2 else { return h }
        let lastTwo = parts.suffix(2).joined(separator: ".")
        if twoLevelTLDs.contains(lastTwo), parts.count >= 3 { return parts.suffix(3).joined(separator: ".") }
        return lastTwo
    }

    private static func isIP(_ h: String) -> Bool {
        h.contains(":") || h.allSatisfy { $0.isNumber || $0 == "." }
    }
}
