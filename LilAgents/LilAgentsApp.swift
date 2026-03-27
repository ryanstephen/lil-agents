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
    private var bruceProviderMenu: NSMenu?
    private var jazzProviderMenu: NSMenu?
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

        let char1Item = NSMenuItem(title: "Bruce", action: #selector(toggleChar1), keyEquivalent: "1")
        char1Item.state = .on
        menu.addItem(char1Item)

        let char2Item = NSMenuItem(title: "Jazz", action: #selector(toggleChar2), keyEquivalent: "2")
        char2Item.state = .on
        menu.addItem(char2Item)

        menu.addItem(NSMenuItem.separator())

        let soundItem = NSMenuItem(title: "Sounds", action: #selector(toggleSounds(_:)), keyEquivalent: "")
        soundItem.state = .on
        menu.addItem(soundItem)

        // Provider submenus (one per character)
        let bruceProviderItem = NSMenuItem(title: "Bruce Provider", action: nil, keyEquivalent: "")
        let bruceMenu = NSMenu()
        for (i, provider) in AgentProvider.allCases.enumerated() {
            let item = NSMenuItem(title: provider.displayName, action: #selector(switchCharacterProvider(_:)), keyEquivalent: "")
            item.tag = 0 * 100 + i
            bruceMenu.addItem(item)
        }
        bruceProviderItem.submenu = bruceMenu
        bruceProviderMenu = bruceMenu
        menu.addItem(bruceProviderItem)

        let jazzProviderItem = NSMenuItem(title: "Jazz Provider", action: nil, keyEquivalent: "")
        let jazzMenu = NSMenu()
        for (i, provider) in AgentProvider.allCases.enumerated() {
            let item = NSMenuItem(title: provider.displayName, action: #selector(switchCharacterProvider(_:)), keyEquivalent: "")
            item.tag = 1 * 100 + i
            jazzMenu.addItem(item)
        }
        jazzProviderItem.submenu = jazzMenu
        jazzProviderMenu = jazzMenu
        menu.addItem(jazzProviderItem)

        // Theme submenu
        let themeItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for (i, theme) in PopoverTheme.allThemes.enumerated() {
            let item = NSMenuItem(title: theme.name, action: #selector(switchTheme(_:)), keyEquivalent: "")
            item.tag = i
            item.state = i == 0 ? .on : .off
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

        syncProviderMenuCheckmarks()
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

    private func syncProviderMenuCheckmarks() {
        guard let chars = controller?.characters, chars.count >= 2 else { return }
        let allProviders = AgentProvider.allCases
        let bruce = chars[0].agentProvider
        let jazz = chars[1].agentProvider
        if let m = bruceProviderMenu {
            for item in m.items {
                let i = item.tag % 100
                guard i < allProviders.count else { continue }
                item.state = allProviders[i] == bruce ? .on : .off
            }
        }
        if let m = jazzProviderMenu {
            for item in m.items {
                let i = item.tag % 100
                guard i < allProviders.count else { continue }
                item.state = allProviders[i] == jazz ? .on : .off
            }
        }
    }

    @objc func switchCharacterProvider(_ sender: NSMenuItem) {
        let charIdx = sender.tag / 100
        let provIdx = sender.tag % 100
        let allProviders = AgentProvider.allCases
        guard provIdx < allProviders.count,
              let chars = controller?.characters,
              charIdx < chars.count else { return }

        let char = chars[charIdx]
        char.agentProvider = allProviders[provIdx]

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

        syncProviderMenuCheckmarks()
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

    @objc func toggleChar1(_ sender: NSMenuItem) {
        guard let chars = controller?.characters, chars.count > 0 else { return }
        let char = chars[0]
        if char.window.isVisible {
            char.window.orderOut(nil)
            char.queuePlayer.pause()
            sender.state = .off
        } else {
            char.window.orderFrontRegardless()
            sender.state = .on
        }
    }

    @objc func toggleChar2(_ sender: NSMenuItem) {
        guard let chars = controller?.characters, chars.count > 1 else { return }
        let char = chars[1]
        if char.window.isVisible {
            char.window.orderOut(nil)
            char.queuePlayer.pause()
            sender.state = .off
        } else {
            char.window.orderFrontRegardless()
            sender.state = .on
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

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {}
