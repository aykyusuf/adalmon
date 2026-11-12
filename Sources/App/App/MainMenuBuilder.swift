import AppKit

/// Dock modunda görünen uygulama menüsü: Adalmon, Düzen, Görünüm, Pencere, Yardım.
@MainActor
enum MainMenuBuilder {
    /// - Parameter target: `openSettings(_:)` ve `showMainWindow(_:)` eylemlerini karşılayan nesne.
    static func make(target: AppDelegate) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenuItem(appMenu(target: target)))
        main.addItem(submenuItem(editMenu()))
        main.addItem(submenuItem(viewMenu()))
        let window = windowMenu(target: target)
        main.addItem(submenuItem(window))
        NSApp.windowsMenu = window
        let help = helpMenu()
        main.addItem(submenuItem(help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    private static func appMenu(target: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Adalmon")
        menu.addItem(item("Adalmon Hakkında", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Ayarlar…", #selector(AppDelegate.openSettings(_:)), ",", target: target))
        menu.addItem(.separator())
        menu.addItem(item("Adalmon'u Gizle", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Diğerlerini Gizle", #selector(NSApplication.hideOtherApplications(_:)), "h",
                          modifiers: [.command, .option]))
        menu.addItem(item("Tümünü Göster", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Adalmon'dan Çık", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    /// Arama alanı için kopyala/yapıştır kısayolları.
    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Düzen")
        menu.addItem(item("Geri Al", Selector(("undo:")), "z"))
        menu.addItem(item("Yinele", Selector(("redo:")), "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Kes", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Kopyala", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Yapıştır", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Tümünü Seç", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        menu.addItem(item("Ara", #selector(MainWindowCommands.focusSearch(_:)), "f", target: MainWindowCommands.shared))
        return menu
    }

    /// "Görünüm": sayfa kısayolları (⌘1…⌘9), kenar çubuğu ve tam ekran.
    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "Görünüm")
        for section in MainSection.pages {
            let entry = item(section.title, #selector(MainWindowCommands.selectSection(_:)), section.shortcutKey ?? "",
                             target: MainWindowCommands.shared)
            entry.representedObject = section.id
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item("Kenar Çubuğunu Gizle/Göster", #selector(NSSplitViewController.toggleSidebar(_:)), "s",
                          modifiers: [.command, .control]))
        menu.addItem(item("Tam Ekran", #selector(NSWindow.toggleFullScreen(_:)), "f", modifiers: [.command, .control]))
        return menu
    }

    /// Boş "Yardım" menüsü: macOS buraya otomatik menü arama alanını ekler (⌘? ile tüm menü komutlarında arama).
    private static func helpMenu() -> NSMenu {
        NSMenu(title: "Yardım")
    }

    private static func windowMenu(target: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Pencere")
        menu.addItem(item("Ana pencere", #selector(AppDelegate.showMainWindow(_:)), "0",
                          modifiers: [.command, .option], target: target))
        menu.addItem(item("Ajan ofisi penceresi", #selector(AppDelegate.showOfficeWindow(_:)), "9",
                          modifiers: [.command, .option], target: target))
        menu.addItem(.separator())
        menu.addItem(item("Küçült", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Yakınlaştır", #selector(NSWindow.performZoom(_:))))
        menu.addItem(item("Kapat", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(.separator())
        menu.addItem(item("Hepsini Öne Getir", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}
