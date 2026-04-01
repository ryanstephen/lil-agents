import SwiftUI
import AppKit
import Sparkle

@main
struct LilAgentsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: LilAgentsController?
    var statusItem: NSStatusItem?
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = LilAgentsController()
        controller?.start()
        setupMenuBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.characters.forEach { $0.session?.terminate() }
    }

    // MARK: - Menu Bar

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "figure.walk", accessibilityDescription: "lil agents")
        }

        let menu = NSMenu()

        // Per-character submenus
        if let chars = controller?.characters {
            let shortcuts = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
            for (ci, char) in chars.enumerated() {
                let charItem = NSMenuItem(title: char.characterId.capitalized, action: nil, keyEquivalent: "")
                let charMenu = NSMenu()
                charMenu.delegate = self

                // Show/Hide toggle
                let shortcut = ci < shortcuts.count ? shortcuts[ci] : ""
                let visItem = NSMenuItem(title: "Show/Hide", action: #selector(toggleCharVisibility(_:)), keyEquivalent: shortcut)
                visItem.representedObject = char
                visItem.state = char.isManuallyVisible ? .on : .off
                charMenu.addItem(visItem)

                charMenu.addItem(NSMenuItem.separator())

                // Provider submenu
                let providerItem = NSMenuItem(title: "Provider", action: nil, keyEquivalent: "")
                let providerMenu = NSMenu()
                providerMenu.delegate = self
                for (i, provider) in AgentProvider.allCases.enumerated() {
                    let item = NSMenuItem(title: provider.displayName, action: #selector(switchCharProvider(_:)), keyEquivalent: "")
                    item.tag = i
                    item.representedObject = char
                    item.state = provider == char.config.provider ? .on : .off
                    providerMenu.addItem(item)
                }
                providerItem.submenu = providerMenu
                charMenu.addItem(providerItem)

                // Size submenu
                let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
                let sizeMenu = NSMenu()
                sizeMenu.delegate = self
                for (i, size) in CharacterSize.allCases.reversed().enumerated() {
                    let item = NSMenuItem(title: size.displayName, action: #selector(switchCharSize(_:)), keyEquivalent: "")
                    item.tag = i
                    item.representedObject = char
                    item.state = size == char.config.size ? .on : .off
                    sizeMenu.addItem(item)
                }
                sizeItem.submenu = sizeMenu
                charMenu.addItem(sizeItem)

                // Working Directory submenu
                let dirItem = NSMenuItem(title: "Working Directory", action: nil, keyEquivalent: "")
                let dirMenu = NSMenu()
                dirMenu.delegate = self
                rebuildDirectoryMenu(dirMenu, for: char)
                dirItem.submenu = dirMenu
                charMenu.addItem(dirItem)

                charItem.submenu = charMenu
                menu.addItem(charItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let soundItem = NSMenuItem(title: "Sounds", action: #selector(toggleSounds(_:)), keyEquivalent: "")
        soundItem.state = .on
        menu.addItem(soundItem)

        // Theme submenu
        let themeItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for (i, theme) in PopoverTheme.allThemes.enumerated() {
            let item = NSMenuItem(title: theme.name, action: #selector(switchTheme(_:)), keyEquivalent: "")
            item.tag = i
            item.state = theme.name == PopoverTheme.current.name ? .on : .off
            themeMenu.addItem(item)
        }
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

        // Display submenu
        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu()
        displayMenu.delegate = self
        let autoItem = NSMenuItem(title: "Auto (Main Display)", action: #selector(switchDisplay(_:)), keyEquivalent: "")
        autoItem.tag = -1
        autoItem.state = .on
        displayMenu.addItem(autoItem)
        displayMenu.addItem(NSMenuItem.separator())
        for (i, screen) in NSScreen.screens.enumerated() {
            let name = screen.localizedName
            let item = NSMenuItem(title: name, action: #selector(switchDisplay(_:)), keyEquivalent: "")
            item.tag = i
            item.state = .off
            displayMenu.addItem(item)
        }
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)

        menu.addItem(NSMenuItem.separator())

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updaterController
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - Menu Actions

    @objc func switchTheme(_ sender: NSMenuItem) {
        let idx = sender.tag
        guard idx < PopoverTheme.allThemes.count else { return }
        PopoverTheme.current = PopoverTheme.allThemes[idx]

        if let themeMenu = sender.menu {
            for item in themeMenu.items {
                item.state = item.tag == idx ? .on : .off
            }
        }

        controller?.characters.forEach { char in
            let wasOpen = char.isIdleForPopover
            if wasOpen { char.popoverWindow?.orderOut(nil) }
            char.popoverWindow = nil
            char.terminalView = nil
            char.thinkingBubbleWindow = nil
            if wasOpen {
                char.createPopoverWindow()
                if let session = char.session, !session.history.isEmpty {
                    char.terminalView?.replayHistory(session.history)
                }
                char.updatePopoverPosition()
                char.popoverWindow?.orderFrontRegardless()
                char.popoverWindow?.makeKey()
                if let terminal = char.terminalView {
                    char.popoverWindow?.makeFirstResponder(terminal.inputField)
                }
            }
        }
    }

    @objc func toggleCharVisibility(_ sender: NSMenuItem) {
        guard let char = sender.representedObject as? WalkerCharacter else { return }
        if char.isManuallyVisible {
            char.setManuallyVisible(false)
            sender.state = .off
        } else {
            char.setManuallyVisible(true)
            sender.state = .on
        }
    }

    @objc func switchCharProvider(_ sender: NSMenuItem) {
        guard let char = sender.representedObject as? WalkerCharacter else { return }
        let idx = sender.tag
        let allProviders = AgentProvider.allCases
        guard idx < allProviders.count else { return }
        char.config.provider = allProviders[idx]

        if let providerMenu = sender.menu {
            for item in providerMenu.items {
                item.state = item.tag == idx ? .on : .off
            }
        }

        resetCharSession(char)
    }

    @objc func switchCharSize(_ sender: NSMenuItem) {
        guard let char = sender.representedObject as? WalkerCharacter else { return }
        let idx = sender.tag
        let allSizes = CharacterSize.allCases.reversed() as [CharacterSize]
        guard idx < allSizes.count else { return }
        char.config.size = allSizes[idx]

        if let sizeMenu = sender.menu {
            for item in sizeMenu.items {
                item.state = item.tag == idx ? .on : .off
            }
        }

        char.applySize()
    }

    @objc func switchDisplay(_ sender: NSMenuItem) {
        let idx = sender.tag
        controller?.pinnedScreenIndex = idx

        if let displayMenu = sender.menu {
            for item in displayMenu.items {
                item.state = item.tag == idx ? .on : .off
            }
        }
    }

    @objc func toggleDebug(_ sender: NSMenuItem) {
        guard let debugWin = controller?.debugWindow else { return }
        if debugWin.isVisible {
            debugWin.orderOut(nil)
            sender.state = .off
        } else {
            debugWin.orderFrontRegardless()
            sender.state = .on
        }
    }

    @objc func toggleSounds(_ sender: NSMenuItem) {
        WalkerCharacter.soundsEnabled.toggle()
        sender.state = WalkerCharacter.soundsEnabled ? .on : .off
    }

    // MARK: - Per-Character Working Directory

    private func rebuildDirectoryMenu(_ menu: NSMenu, for char: WalkerCharacter) {
        menu.removeAllItems()

        let home = FileManager.default.homeDirectoryForCurrentUser
        let currentURL = char.config.workingDirectoryURL
        let isHome = currentURL.standardizedFileURL == home.standardizedFileURL

        let homeItem = NSMenuItem(title: "Home (~/)", action: #selector(resetCharWorkingDirectory(_:)), keyEquivalent: "")
        homeItem.representedObject = char
        homeItem.state = isHome ? .on : .off
        menu.addItem(homeItem)

        if !isHome {
            let displayPath = (currentURL.path as NSString).abbreviatingWithTildeInPath
            let customItem = NSMenuItem(title: displayPath, action: nil, keyEquivalent: "")
            customItem.state = .on
            menu.addItem(customItem)
        }

        menu.addItem(NSMenuItem.separator())

        let chooseItem = NSMenuItem(title: "Choose\u{2026}", action: #selector(chooseCharWorkingDirectory(_:)), keyEquivalent: "")
        chooseItem.representedObject = char
        menu.addItem(chooseItem)
    }

    @objc func chooseCharWorkingDirectory(_ sender: NSMenuItem) {
        guard let char = sender.representedObject as? WalkerCharacter else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose a working directory for \(char.characterId.capitalized)"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            char.config.workingDirectoryURL = url
            self?.resetCharSession(char)
            if let dirMenu = sender.menu {
                self?.rebuildDirectoryMenu(dirMenu, for: char)
            }
        }
    }

    @objc func resetCharWorkingDirectory(_ sender: NSMenuItem) {
        guard let char = sender.representedObject as? WalkerCharacter else { return }
        char.config.workingDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        resetCharSession(char)
        if let dirMenu = sender.menu {
            rebuildDirectoryMenu(dirMenu, for: char)
        }
    }

    private func resetCharSession(_ char: WalkerCharacter) {
        char.session?.terminate()
        char.session = nil
        if char.isIdleForPopover {
            char.closePopover()
        }
        char.popoverWindow?.orderOut(nil)
        char.popoverWindow = nil
        char.terminalView = nil
        char.thinkingBubbleWindow?.orderOut(nil)
        char.thinkingBubbleWindow = nil
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Refresh per-character directory submenus when opened
        guard let chars = controller?.characters else { return }
        for char in chars {
            // Find this character's submenu by checking the title
            if let charItem = statusItem?.menu?.item(withTitle: char.characterId.capitalized),
               let charMenu = charItem.submenu,
               let dirItem = charMenu.item(withTitle: "Working Directory"),
               menu == dirItem.submenu {
                rebuildDirectoryMenu(menu, for: char)
                return
            }
        }

        // Refresh per-character size submenus when opened
        for char in chars {
            if let charItem = statusItem?.menu?.item(withTitle: char.characterId.capitalized),
               let charMenu = charItem.submenu,
               let sizeItem = charMenu.item(withTitle: "Size"),
               menu == sizeItem.submenu {
                let allSizes = CharacterSize.allCases.reversed() as [CharacterSize]
                for item in menu.items {
                    if item.tag < allSizes.count {
                        item.state = allSizes[item.tag] == char.config.size ? .on : .off
                    }
                }
                return
            }
        }

        // Refresh per-character provider submenus when opened
        for char in chars {
            if let charItem = statusItem?.menu?.item(withTitle: char.characterId.capitalized),
               let charMenu = charItem.submenu,
               let providerItem = charMenu.item(withTitle: "Provider"),
               menu == providerItem.submenu {
                for item in menu.items {
                    let allProviders = AgentProvider.allCases
                    if item.tag < allProviders.count {
                        item.state = allProviders[item.tag] == char.config.provider ? .on : .off
                    }
                }
                return
            }
        }

        // Refresh show/hide state
        for char in chars {
            if let charItem = statusItem?.menu?.item(withTitle: char.characterId.capitalized),
               menu == charItem.submenu {
                if let visItem = menu.item(withTitle: "Show/Hide") {
                    visItem.state = char.isManuallyVisible ? .on : .off
                }
                return
            }
        }
    }
}
