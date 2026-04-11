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
        controller?.characters.forEach {
            $0.session?.terminate()
            $0.terminateAllDetachedSessions()
        }
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

        // Provider submenu (applies to all characters)
        let providerItem = NSMenuItem(title: "Provider", action: nil, keyEquivalent: "")
        let providerMenu = NSMenu()
        let currentProvider = controller?.characters.first?.provider ?? .claude
        for (i, provider) in AgentProvider.allCases.enumerated() {
            let item = NSMenuItem(title: provider.displayName, action: #selector(switchProvider(_:)), keyEquivalent: "")
            item.tag = i
            item.state = provider == currentProvider ? .on : .off
            if !provider.isAvailable {
                item.isEnabled = false
            }
            providerMenu.addItem(item)
        }
        providerMenu.addItem(NSMenuItem.separator())
        let gatewayItem = NSMenuItem(title: "Advanced Settings\u{2026}", action: #selector(openGatewaySettings), keyEquivalent: "")
        gatewayItem.tag = -1
        providerMenu.addItem(gatewayItem)

        providerItem.submenu = providerMenu
        menu.addItem(providerItem)

        // Size submenu (applies to all characters)
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        let currentSize = controller?.characters.first?.size ?? .large
        for (i, size) in CharacterSize.allCases.enumerated() {
            let item = NSMenuItem(title: size.displayName, action: #selector(switchCharacterSize(_:)), keyEquivalent: "")
            item.tag = i
            item.state = size == currentSize ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

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
            if char.hasDetachedChats {
                char.refreshDetachedChromeTheme()
                char.reapplyAppearanceToAllDetachedTerminals()
            }
            let wasOpen = char.isIdleForPopover
            if wasOpen { char.popoverWindow?.orderOut(nil) }
            char.popoverWindow = nil
            char.terminalView = nil
            char.thinkingBubbleWindow = nil
            if wasOpen {
                char.createPopoverWindow()
                char.rewirePopoverSessionIfNeeded()
                if let session = char.session, !session.history.isEmpty {
                    char.terminalView?.replayHistory(session.history)
                }
                char.updatePopoverPosition()
                char.ensurePopoverAboveCharacterWindow()
                char.popoverWindow?.orderFrontRegardless()
                char.popoverWindow?.makeKey()
                if let terminal = char.terminalView {
                    char.popoverWindow?.makeFirstResponder(terminal.inputField)
                }
            }
        }
    }

    @objc func switchProvider(_ sender: NSMenuItem) {
        let idx = sender.tag
        let allProviders = AgentProvider.allCases
        guard idx < allProviders.count else { return }
        let newProvider = allProviders[idx]

        controller?.characters.forEach { char in
            if char.provider == newProvider { return }
            char.provider = newProvider
            char.discardDetachedChatSilently()
            char.session?.terminate()
            char.session = nil
            char.popoverWindow?.orderOut(nil)
            char.popoverWindow = nil
            char.terminalView = nil
            char.thinkingBubbleWindow?.orderOut(nil)
            char.thinkingBubbleWindow = nil
        }

        if let providerMenu = sender.menu {
            for item in providerMenu.items {
                item.state = item.tag == idx ? .on : .off
            }
        }
    }

    @objc func switchCharacterSize(_ sender: NSMenuItem) {
        let idx = sender.tag
        let allSizes = CharacterSize.allCases
        guard idx < allSizes.count else { return }
        let newSize = allSizes[idx]

        controller?.characters.forEach { $0.size = newSize }

        if let sizeMenu = sender.menu {
            for item in sizeMenu.items {
                item.state = item.tag == idx ? .on : .off
            }
        }
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
        if char.isManuallyVisible {
            char.setManuallyVisible(false)
            sender.state = .off
        } else {
            char.setManuallyVisible(true)
            sender.state = .on
        }
    }

    @objc func toggleChar2(_ sender: NSMenuItem) {
        guard let chars = controller?.characters, chars.count > 1 else { return }
        let char = chars[1]
        if char.isManuallyVisible {
            char.setManuallyVisible(false)
            sender.state = .off
        } else {
            char.setManuallyVisible(true)
            sender.state = .on
        }
    }

    @objc func toggleSounds(_ sender: NSMenuItem) {
        WalkerCharacter.soundsEnabled.toggle()
        sender.state = WalkerCharacter.soundsEnabled ? .on : .off
    }

    @objc func openGatewaySettings() {
        OpenClawSession.showSettingsPanel { [weak self] in
            // If OpenClaw is the active provider, reconnect with new settings
            guard AgentProvider.current == .openclaw else { return }
            self?.controller?.characters.forEach { char in
                char.session?.terminate()
                char.session = nil
            }
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {}
