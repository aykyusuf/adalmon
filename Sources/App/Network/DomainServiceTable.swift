/// Bilinen servislerin alan adı (son ek) → görünen ad tablosu. En uzun eşleşen son ek kazanır
/// (ör. `youtubei.googleapis.com` → YouTube, `googleapis.com` → Google).
enum DomainServiceTable {
    static let cdnSuffix = " (CDN)"

    /// (görünen ad, alan adı son ekleri)
    static let services: [(name: String, domains: [String])] = [
        ("YouTube", ["googlevideo.com", "youtube.com", "ytimg.com", "ggpht.com", "youtu.be", "youtube-nocookie.com",
                     "youtubei.googleapis.com", "yt.be"]),
        ("Google", ["google.com", "google.com.tr", "gstatic.com", "googleapis.com", "googleusercontent.com", "gvt1.com", "gvt2.com",
                    "google-analytics.com", "googletagmanager.com", "googlesyndication.com", "googleadservices.com",
                    "doubleclick.net", "app-measurement.com", "withgoogle.com", "firebaseio.com", "firebase.google.com",
                    "gcr.io", "gmail.com", "goo.gl", "g.co"]),
        ("Apple", ["apple.com", "aaplimg.com", "mzstatic.com", "cdn-apple.com", "apple-dns.net", "apple.news", "itunes.com"]),
        ("iCloud", ["icloud.com", "icloud-content.com", "apple-cloudkit.com", "me.com", "icloud.com.cn"]),
        ("GitHub", ["github.com", "githubusercontent.com", "githubassets.com", "github.io", "ghcr.io", "githubapp.com",
                    "githubcopilot.com", "git.io"]),
        ("Cloudflare", ["cloudflare.com", "cloudflare-dns.com", "cloudflarestorage.com", "cloudflareinsights.com",
                        "workers.dev", "pages.dev", "r2.dev", "trycloudflare.com"]),
        ("Claude", ["anthropic.com", "claude.ai", "claude.com", "claudeusercontent.com"]),
        ("OpenAI", ["openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com"]),
        ("Spotify", ["spotify.com", "scdn.co", "spotifycdn.com", "spotifycdn.net", "spotilocal.com"]),
        ("Netflix", ["netflix.com", "nflxvideo.net", "nflximg.net", "nflxso.net", "nflxext.com"]),
        ("Disney+", ["disneyplus.com", "disney-plus.net", "bamgrid.com", "dssott.com", "disney.com"]),
        ("WhatsApp", ["whatsapp.net", "whatsapp.com", "wa.me"]),
        ("Instagram", ["instagram.com", "cdninstagram.com"]),
        ("Facebook", ["facebook.com", "facebook.net", "fbcdn.net", "fb.com", "fb.me", "fbsbx.com", "messenger.com"]),
        ("Telegram", ["telegram.org", "telegram.me", "t.me", "cdn-telegram.org", "telesco.pe", "tdesktop.com"]),
        ("Discord", ["discord.com", "discord.gg", "discordapp.com", "discordapp.net", "discord.media"]),
        ("Twitch", ["twitch.tv", "ttvnw.net", "jtvnw.net", "twitchcdn.net"]),
        ("X", ["twitter.com", "x.com", "twimg.com", "t.co"]),
        ("LinkedIn", ["linkedin.com", "licdn.com"]),
        ("Reddit", ["reddit.com", "redd.it", "redditmedia.com", "redditstatic.com"]),
        ("TikTok", ["tiktok.com", "tiktokcdn.com", "tiktokv.com", "byteoversea.com", "ibytedtos.com", "muscdn.com"]),
        ("Microsoft", ["microsoft.com", "live.com", "office.com", "office365.com", "microsoftonline.com", "msn.com", "bing.com",
                       "skype.com", "sharepoint.com", "onedrive.com", "1drv.com", "visualstudio.com", "vscode-cdn.net",
                       "msftconnecttest.com", "windows.com", "windows.net", "msauth.net", "msecnd.net", "outlook.com"]),
        ("Amazon", ["amazon.com", "amazon.com.tr", "amazon.de", "media-amazon.com", "ssl-images-amazon.com", "primevideo.com",
                    "amazon-adsystem.com"]),
        ("Amazon AWS", ["amazonaws.com", "awsstatic.com", "aws.amazon.com", "amazonaws.com.cn", "awsglobalaccelerator.com",
                        "amazoncognito.com"]),
        ("Steam", ["steampowered.com", "steamcontent.com", "steamstatic.com", "steamcommunity.com", "valvesoftware.com"]),
        ("Zoom", ["zoom.us", "zoom.com", "zoomgov.com"]),
        ("Slack", ["slack.com", "slack-edge.com", "slack-msgs.com"]),
        ("Dropbox", ["dropbox.com", "dropboxusercontent.com", "dropboxapi.com"]),
        ("Mozilla", ["mozilla.org", "mozilla.net", "mozilla.com", "firefox.com"]),
        ("Wikipedia", ["wikipedia.org", "wikimedia.org"]),
        ("Datadog", ["datadoghq.com", "datadoghq.eu", "datad0g.com"]),
        ("Sentry", ["sentry.io", "sentry-cdn.com"]),
        ("Setapp", ["setapp.com"]),
        ("Raycast", ["raycast.com", "raycast-releases.com"]),
        ("Warp", ["warp.dev"]),
        ("Deno", ["deno.dev", "deno.com", "deno.land"]),
        ("Dart / Flutter", ["dart.dev", "pub.dev", "flutter.dev", "flutter-io.cn"]),
        ("npm", ["npmjs.org", "npmjs.com"]),
        ("Docker", ["docker.com", "docker.io"]),
        ("Homebrew", ["brew.sh", "homebrew.org"]),
        ("Vercel", ["vercel.com", "vercel.app", "vercel-dns.com"]),
        ("Supabase", ["supabase.co", "supabase.com", "supabase.in"]),
        // CDN'ler: asıl içerik sahibi bilinmez, dürüstçe "CDN" diye etiketlenir.
        ("Akamai (CDN)", ["akamai.net", "akamaiedge.net", "akamaihd.net", "akamaized.net", "akamaitechnologies.com",
                          "edgekey.net", "edgesuite.net", "akadns.net", "akamai.com"]),
        ("CloudFront (CDN)", ["cloudfront.net"]),
        ("Fastly (CDN)", ["fastly.net", "fastlylb.net", "fastly.com", "fastly-edge.com"]),
        ("Azure (CDN)", ["azureedge.net", "azurefd.net", "trafficmanager.net"]),
        ("jsDelivr (CDN)", ["jsdelivr.net"]),
        ("Bunny (CDN)", ["b-cdn.net", "bunnycdn.com"]),
    ]

    /// Son ek → görünen ad.
    static let bySuffix: [String: String] = {
        var m: [String: String] = [:]
        for (name, domains) in services { for d in domains { m[d] = name } }
        return m
    }()

    /// Görünen adların küçük harfli hâli → kanonik yazım (grup adı yeniden gruplanınca değişmesin: idempotent).
    static let canonicalNames: [String: String] = {
        var m: [String: String] = [:]
        for (name, _) in services { m[name.lowercased()] = name }
        return m
    }()

    /// `host`un (küçük harfli) en uzun eşleşen servis son ekini bulur.
    static func service(for host: String) -> String? {
        var s = Substring(host)
        while true {
            if let name = bySuffix[String(s)] { return name }
            guard let dot = s.firstIndex(of: ".") else { return nil }
            s = s[s.index(after: dot)...]
        }
    }
}
