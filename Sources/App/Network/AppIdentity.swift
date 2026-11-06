/// Bir uygulama anahtarının (`UsageBucket.app`) insan dostu kimliği. Yalnızca gösterim içindir; anahtarın kendisi
/// (limit/engel/kural eşleşmesi) asla değişmez.
struct AppIdentity: Sendable, Equatable {
    var name: String
    var kind: AppKind
    /// İkonu başka bir uygulamadan ödünç almak için paket kimliği (ör. WebKit.Networking → Safari).
    var iconBundleID: String?
}
