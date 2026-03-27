import AppKit

class LilAgentsController {
    var characters: [WalkerCharacter] = []
    private var displayLink: CVDisplayLink?
    var debugWindow: NSWindow?
    var pinnedScreenIndex: Int = -1
    private static let onboardingKey = "hasCompletedOnboarding"
    private var isHiddenForEnvironment = false

    // MARK: - Auto-hide Dock Dodging

    /// Whether the cursor is currently in the dock trigger zone (bottom 5px of screen).
    private var mouseInDockZone = false

    /// Smoothed Y offset for character position when dock auto-hides.
    private var smoothedDockOffset: CGFloat = 0
    private static let dockSmoothFactor: CGFloat = 0.12

    /// Estimated dock height from the tile size preference (~tileSize + 22px padding)
    private var estimatedDockHeight: CGFloat {
        let tileSize = CGFloat(UserDefaults(suiteName: "com.apple.dock")?.double(forKey: "tilesize") ?? 48)
        return tileSize + 22
    }

    /// Event monitors for mouse movement — fires only when the cursor actually moves.
    private var dockMouseMonitor: Any?
    private var dockLocalMouseMonitor: Any?

    private func setupDockMouseMonitor() {
        dockMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.updateDockZoneFromMouse()
        }
        dockLocalMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.updateDockZoneFromMouse()
            return nil
        }
    }

    private func updateDockZoneFromMouse() {
        guard dockAutohideEnabled(), let screen = activeScreen else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screenBottom = screen.frame.origin.y
        mouseInDockZone = mouseLocation.y - screenBottom < 5
    }

    func start() {
        let char1 = WalkerCharacter(videoName: "walk-bruce-01")
        char1.accelStart = 3.0
        char1.fullSpeedStart = 3.75
        char1.decelStart = 8.0
        char1.walkStop = 8.5
        char1.walkAmountRange = 0.4...0.65

        let char2 = WalkerCharacter(videoName: "walk-jazz-01")
        char2.accelStart = 3.9
        char2.fullSpeedStart = 4.5
        char2.decelStart = 8.0
        char2.walkStop = 8.75
        char2.walkAmountRange = 0.35...0.6
        char1.yOffset = -3
        char2.yOffset = -7
        char1.characterColor = NSColor(red: 0.4, green: 0.72, blue: 0.55, alpha: 1.0)
        char2.characterColor = NSColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0)

        char1.flipXOffset = 0
        char2.flipXOffset = -9

        char1.positionProgress = 0.3
        char2.positionProgress = 0.7

        char1.pauseEndTime = CACurrentMediaTime() + Double.random(in: 0.5...2.0)
        char2.pauseEndTime = CACurrentMediaTime() + Double.random(in: 8.0...14.0)

        char1.setup()
        char2.setup()

        characters = [char1, char2]
        characters.forEach { $0.controller = self }

        setupDebugLine()
        setupDockMouseMonitor()
        startDisplayLink()

        if !UserDefaults.standard.bool(forKey: Self.onboardingKey) {
            triggerOnboarding()
        }
    }

    private func triggerOnboarding() {
        guard let bruce = characters.first else { return }
        bruce.isOnboarding = true
        // Show "hi!" bubble after a short delay so the character is visible first
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            bruce.currentPhrase = "hi!"
            bruce.showingCompletion = true
            bruce.completionBubbleExpiry = CACurrentMediaTime() + 600 // stays until clicked
            bruce.showBubble(text: "hi!", isCompletion: true)
            bruce.playCompletionSound()
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        characters.forEach { $0.isOnboarding = false }
    }

    // MARK: - Debug

    private func setupDebugLine() {
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 2),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = NSColor.red
        win.hasShadow = false
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 10)
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.moveToActiveSpace, .stationary]
        win.orderOut(nil)
        debugWindow = win
    }

    private func updateDebugLine(dockX: CGFloat, dockWidth: CGFloat, dockTopY: CGFloat) {
        guard let win = debugWindow, win.isVisible else { return }
        win.setFrame(CGRect(x: dockX, y: dockTopY, width: dockWidth, height: 2), display: true)
    }

    // MARK: - Dock Geometry

    private func getDockIconArea(screenWidth: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        let tileSize = CGFloat(dockDefaults?.double(forKey: "tilesize") ?? 48)
        // Each dock slot is the icon + padding. The padding scales with tile size.
        // At default 48pt: slot ≈ 58pt. At 37pt: slot ≈ 47pt. Roughly tileSize * 1.25.
        let slotWidth = tileSize * 1.25

        let persistentApps = dockDefaults?.array(forKey: "persistent-apps")?.count ?? 0
        let persistentOthers = dockDefaults?.array(forKey: "persistent-others")?.count ?? 0

        // Only count recent apps if show-recents is enabled
        let showRecents = dockDefaults?.bool(forKey: "show-recents") ?? true
        let recentApps = showRecents ? (dockDefaults?.array(forKey: "recent-apps")?.count ?? 0) : 0
        let totalIcons = persistentApps + persistentOthers + recentApps

        var dividers = 0
        if persistentApps > 0 && (persistentOthers > 0 || recentApps > 0) { dividers += 1 }
        if persistentOthers > 0 && recentApps > 0 { dividers += 1 }
        // show-recents adds its own divider
        if showRecents && recentApps > 0 { dividers += 1 }

        let dividerWidth: CGFloat = 12.0
        var dockWidth = slotWidth * CGFloat(totalIcons) + CGFloat(dividers) * dividerWidth

        let magnificationEnabled = dockDefaults?.bool(forKey: "magnification") ?? false
        if magnificationEnabled,
           let largeSize = dockDefaults?.object(forKey: "largesize") as? CGFloat {
            // Magnification only affects the hovered area; at rest the dock is normal size.
            // Don't inflate the width — characters should stay within the at-rest bounds.
            _ = largeSize
        }

        // Small fudge factor for dock edge padding
        dockWidth *= 1.1
        let dockX = (screenWidth - dockWidth) / 2.0
        return (dockX, dockWidth)
    }

    private func dockAutohideEnabled() -> Bool {
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        return dockDefaults?.bool(forKey: "autohide") ?? false
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink = displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            let controller = Unmanaged<LilAgentsController>.fromOpaque(userInfo!).takeUnretainedValue()
            DispatchQueue.main.async {
                controller.tick()
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(displayLink, callback,
                                       Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(displayLink)
    }

    var activeScreen: NSScreen? {
        if pinnedScreenIndex >= 0, pinnedScreenIndex < NSScreen.screens.count {
            return NSScreen.screens[pinnedScreenIndex]
        }
        return NSScreen.main
    }

    /// The dock lives on the screen where visibleFrame.origin.y > frame.origin.y (bottom dock)
    /// On screens without the dock, visibleFrame.origin.y == frame.origin.y
    private func screenHasDock(_ screen: NSScreen) -> Bool {
        return screen.visibleFrame.origin.y > screen.frame.origin.y
    }

    private func shouldShowCharacters(on screen: NSScreen) -> Bool {
        if screenHasDock(screen) {
            return true
        }

        // With dock auto-hide enabled on the active desktop, the dock can still be
        // present even though visibleFrame starts at the screen origin. In fullscreen
        // spaces, both the dock and menu bar are absent, so visibleFrame matches frame.
        let menuBarVisible = screen.visibleFrame.maxY < screen.frame.maxY
        return dockAutohideEnabled() && screen == NSScreen.main && menuBarVisible
    }

    @discardableResult
    private func updateEnvironmentVisibility(for screen: NSScreen) -> Bool {
        let shouldShow = shouldShowCharacters(on: screen)
        guard shouldShow != !isHiddenForEnvironment else { return shouldShow }

        isHiddenForEnvironment = !shouldShow

        if shouldShow {
            characters.forEach { $0.showForEnvironmentIfNeeded() }
        } else {
            debugWindow?.orderOut(nil)
            characters.forEach { $0.hideForEnvironment() }
        }

        return shouldShow
    }

    func tick() {
        guard let screen = activeScreen else { return }
        guard updateEnvironmentVisibility(for: screen) else { return }

        let screenWidth = screen.frame.width
        let dockX: CGFloat
        let dockWidth: CGFloat
        var dockTopY: CGFloat

        // Dock is on this screen — constrain to dock area
        (dockX, dockWidth) = getDockIconArea(screenWidth: screenWidth)
        dockTopY = screen.visibleFrame.origin.y

        // When dock auto-hides, smoothly move characters up when cursor
        // enters the dock trigger zone so they don't overlap the dock.
        if !screenHasDock(screen) && dockAutohideEnabled() {
            let targetOffset = mouseInDockZone ? estimatedDockHeight : 0
            smoothedDockOffset += (targetOffset - smoothedDockOffset) * Self.dockSmoothFactor
            dockTopY += smoothedDockOffset
        } else {
            smoothedDockOffset = 0
        }

        updateDebugLine(dockX: dockX, dockWidth: dockWidth, dockTopY: dockTopY)

        let activeChars = characters.filter { $0.window.isVisible && $0.isManuallyVisible }

        let now = CACurrentMediaTime()
        let anyWalking = activeChars.contains { $0.isWalking }
        for char in activeChars {
            if char.isIdleForPopover { continue }
            if char.isPaused && now >= char.pauseEndTime && anyWalking {
                char.pauseEndTime = now + Double.random(in: 5.0...10.0)
            }
        }
        for char in activeChars {
            char.update(dockX: dockX, dockWidth: dockWidth, dockTopY: dockTopY)
        }

        let sorted = activeChars.sorted { $0.positionProgress < $1.positionProgress }
        for (i, char) in sorted.enumerated() {
            char.window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + i)
        }
    }

    deinit {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
        if let monitor = dockMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = dockLocalMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
