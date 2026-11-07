import Foundation

/// Curated, ready-to-add components grouped by category.
enum ComponentLibrary {
    static let entries: [LibraryEntry] = {
        typealias C = MenuBarComponent
        return [
            LibraryEntry("cpu-text", "CPU yüzdesi", .cpu, C(.cpu, showLabel: true)),
            LibraryEntry("cpu-temp-stack", "CPU % ve sıcaklık alt alta", .cpu,
                         C(.cpu, .cpuTemp, visual: .stacked2, colorMode: .threshold, colorTarget: .value, showLabel: true)),
            LibraryEntry("cpu-label-over", "CPU etiket üstte", .cpu, C(.cpu, visual: .stacked2, showLabel: true)),
            LibraryEntry("cpu-bar", "CPU çubuğu", .cpu, C(.cpu, visual: .bar, colorMode: .threshold, showLabel: true, showValue: false)),
            LibraryEntry("cpu-ring", "CPU halkası", .cpu, C(.cpu, visual: .ring, colorMode: .threshold)),
            LibraryEntry("cpu-graph", "CPU grafiği", .cpu, C(.cpu, visual: .sparkline, colorMode: .accent)),
            LibraryEntry("cpu-icon", "CPU ikonlu", .cpu, C(.cpu, visual: .iconValue)),

            LibraryEntry("gpu-ring", "GPU halkası", .gpu, C(.gpu, visual: .ring, colorMode: .threshold)),
            LibraryEntry("gpu-temp-stack", "GPU % ve sıcaklık", .gpu,
                         C(.gpu, .gpuTemp, visual: .stacked2, colorMode: .threshold, colorTarget: .value, showLabel: true)),
            LibraryEntry("gpu-memory", "GPU belleği", .gpu, C(.gpuMemory, showLabel: true)),

            LibraryEntry("mem-free-mb", "Boş bellek (MB)", .memory, C(.memoryFree, showLabel: true, unit: .mb)),
            LibraryEntry("mem-used-free", "Bellek kullanılan / boş", .memory, C(.memoryUsed, .memoryFree, visual: .stacked2, showLabel: true)),
            LibraryEntry("mem-used-gb", "Kullanılan bellek (GB)", .memory, C(.memoryUsed, showLabel: true, unit: .gb)),
            LibraryEntry("mem-ring", "Bellek halkası", .memory, C(.memoryPercent, visual: .ring, colorMode: .gradient)),
            LibraryEntry("mem-bar", "Bellek çubuğu", .memory,
                         C(.memoryPercent, visual: .bar, colorMode: .threshold, showLabel: true, showValue: false)),
            LibraryEntry("mem-graph", "Bellek grafiği", .memory, C(.memoryPercent, visual: .sparkline, colorMode: .custom, customColor: .teal)),
            LibraryEntry("mem-pressure", "Bellek baskısı", .memory,
                         C(.memoryPressure, visual: .dot, colorMode: .threshold, showLabel: true)),
            LibraryEntry("swap", "Swap kullanımı", .memory, C(.swapUsed, showLabel: true)),

            LibraryEntry("disk-free", "Boş disk", .disk, C(.diskFree, showLabel: true, unit: .gb)),
            LibraryEntry("disk-rw", "Disk okuma / yazma", .disk, C(.diskRead, .diskWrite, visual: .stacked2, showLabel: true)),
            LibraryEntry("disk-hbar", "Disk doluluk çubuğu", .disk, C(.diskPercent, visual: .hbar, colorMode: .threshold, showLabel: true)),

            LibraryEntry("temp-cpu-ring", "CPU sıcaklık halkası", .temperature,
                         C(.cpuTemp, visual: .ring, colorMode: .threshold, showLabel: true)),
            LibraryEntry("temp-cpu-gpu", "CPU ve GPU sıcaklığı", .temperature,
                         C(.cpuTemp, .gpuTemp, visual: .stacked2, colorMode: .threshold, colorTarget: .value, showLabel: true)),
            LibraryEntry("temp-gpu", "GPU sıcaklığı", .temperature, C(.gpuTemp, colorMode: .threshold, showLabel: true)),
            LibraryEntry("temp-cpu-max", "En sıcak çekirdek", .temperature, C(.cpuMaxTemp, colorMode: .threshold, showLabel: true)),
            LibraryEntry("temp-ssd", "SSD sıcaklığı", .temperature, C(.ssdTemp, showLabel: true)),
            LibraryEntry("temp-graph", "CPU sıcaklık grafiği", .temperature, C(.cpuTemp, visual: .sparkline, colorMode: .threshold)),

            LibraryEntry("battery-capsule", "Pil kapsülü", .battery, C(.batteryLevel, visual: .batteryCapsule)),
            LibraryEntry("battery-capsule-time", "Pil kapsülü + süre", .battery,
                         C(.batteryLevel, visual: .batteryCapsule, battery: BatteryGlyphOptions(showTime: true))),
            LibraryEntry("battery-text", "Pil yüzdesi", .battery, C(.batteryLevel, showLabel: true)),
            LibraryEntry("battery-ring", "Pil halkası", .battery, C(.batteryLevel, visual: .ring, colorMode: .accent)),
            LibraryEntry("battery-temp", "Pil sıcaklığı", .battery, C(.batteryTemp, showLabel: true)),

            LibraryEntry("net-down", "İndirme hızı", .network, C(.download, showLabel: true)),
            LibraryEntry("net-up", "Yükleme hızı", .network, C(.upload, showLabel: true)),
            LibraryEntry("net-two", "Hız iki satır", .network, C(.upload, .download, visual: .stacked2, showLabel: true)),
            LibraryEntry("net-inline", "Hız tek satır", .network, C(.download, .upload, showLabel: true)),
            LibraryEntry("net-chart", "Ağ grafiği", .network, C(.download, .upload, visual: .sparkline, colorMode: .accent, showValue: false)),
            LibraryEntry("net-down-graph", "İndirme grafiği", .network, C(.download, visual: .sparkline, colorMode: .accent)),
            LibraryEntry("net-today", "Bugünkü trafik", .network,
                         C(.downloadToday, .uploadToday, visual: .stacked2, showLabel: true)),

            LibraryEntry("mobile-hbar", "Mobil kota çubuğu", .mobile, C(.mobileUsed, visual: .hbar, colorMode: .threshold)),
            LibraryEntry("mobile-remaining", "Mobil kalan", .mobile,
                         C(.mobileRemaining, colorMode: .threshold, colorTarget: .value, showLabel: true)),
            LibraryEntry("mobile-ring", "Mobil kota halkası", .mobile, C(.mobilePercent, visual: .ring, colorMode: .threshold)),

            LibraryEntry("conn-dot", "Bağlantı noktası", .connection, C(.connection, visual: .dot, showValue: false)),
            LibraryEntry("conn-icon", "Bağlantı ikonu", .connection, C(.connection, visual: .iconValue, showValue: false)),
            LibraryEntry("conn-text", "Bağlantı adı", .connection, C(.connection)),
        ]
    }()

    static func entries(in category: FieldCategory?) -> [LibraryEntry] {
        guard let category else { return entries }
        return entries.filter { $0.category == category }
    }
}
