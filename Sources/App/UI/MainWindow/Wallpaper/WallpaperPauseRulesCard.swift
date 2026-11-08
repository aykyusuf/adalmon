import SwiftUI

/// Duraklatma kuralları: her biri ayrı anahtar, hepsi varsayılan açık. Duraklatılınca son kare kalır; devam kesintisizdir.
struct WallpaperPauseRulesCard: View {
    @Bindable var service: WallpaperService

    var body: some View {
        RulesCard(title: "Duraklatma kuralları", systemImage: "pause.circle",
                  subtitle: "Duraklatılınca video çözülmez, son kare ekranda kalır; kural kalkınca kaldığı yerden devam eder.") {
            rule("Pildeyken dur", "Mac şarjda değilken oynatmaz.", isOn: $service.settings.rules.pauseOnBattery)
            rule("Düşük Güç Modunda dur", "macOS Düşük Güç Modu açıkken oynatmaz.", isOn: $service.settings.rules.pauseOnLowPower)
            rule("Masaüstü görünmüyorken dur",
                 "Pencereler masaüstünü örtüyorsa (2 sn'de bir, yalnızca oynarken), tam ekran uygulama varsa, ekran kilitli / ekran koruyucu / uykudaysa oynatmaz.",
                 isOn: $service.settings.rules.pauseWhenDesktopHidden)
            rule("Bellek basıncı kritikken dur",
                 "macOS bellek basıncını kritik bildirince durur, uyarı seviyesinde oynamaya devam eder; basınç düşünce kendiliğinden sürer.",
                 isOn: $service.settings.rules.pauseOnMemoryCritical)
            rule("Isınınca dur",
                 "Mac ciddi derecede ısınınca (macOS ısı durumu \"ciddi\" ya da üstü) durur; soğuyunca devam eder.",
                 isOn: $service.settings.rules.pauseOnThermal)
            rule("CPU çok yoğunken dur",
                 "Toplam CPU 30 sn boyunca ortalama %85'in üstündeyse durur; ortalama %60'ın altına inince devam eder. Kısa sıçramalar durdurmaz.",
                 isOn: $service.settings.rules.pauseOnHighCPU)
        }
    }

    private func rule(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: isOn)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
