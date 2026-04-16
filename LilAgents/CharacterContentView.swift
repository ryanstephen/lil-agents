import AppKit

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class CharacterContentView: NSView {
    weak var character: WalkerCharacter?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }

        // AVPlayerLayer is GPU-rendered so layer.render(in:) won't capture video pixels.
        // Use CGWindowListCreateImage to sample actual on-screen alpha at click point.
        let screenPoint = window?.convertPoint(toScreen: convert(localPoint, to: nil)) ?? .zero
        // Use the full virtual display height for the CG coordinate flip, not just
        // the main screen. NSScreen coordinates have origin at bottom-left of the
        // primary display, while CG uses top-left. The primary screen's height is
        // the correct basis for the flip across all monitors.
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let flippedY = primaryScreen.frame.height - screenPoint.y

        let captureRect = CGRect(x: screenPoint.x - 0.5, y: flippedY - 0.5, width: 1, height: 1)
        guard let windowID = window?.windowNumber, windowID > 0 else { return nil }

        if let image = CGWindowListCreateImage(
            captureRect,
            .optionIncludingWindow,
            CGWindowID(windowID),
            [.boundsIgnoreFraming, .bestResolution]
        ) {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var pixel: [UInt8] = [0, 0, 0, 0]
            if let ctx = CGContext(
                data: &pixel, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                if pixel[3] > 30 {
                    return self
                }
                return nil
            }
        }

        // Fallback: accept click if within center 60% of the view
        let insetX = bounds.width * 0.2
        let insetY = bounds.height * 0.15
        let hitRect = bounds.insetBy(dx: insetX, dy: insetY)
        return hitRect.contains(localPoint) ? self : nil
    }

    // Track whether a drag was initiated so we can distinguish click vs drag.
    private var mouseDownScreenPos: NSPoint = .zero
    private var hasDragged = false
    private static let dragThreshold: CGFloat = 4.0

    override func mouseDown(with event: NSEvent) {
        hasDragged = false
        mouseDownScreenPos = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let character = character, let win = window else { return }

        let currentScreenPos = NSEvent.mouseLocation

        if !hasDragged {
            let dx = currentScreenPos.x - mouseDownScreenPos.x
            let dy = currentScreenPos.y - mouseDownScreenPos.y
            guard dx * dx + dy * dy >= Self.dragThreshold * Self.dragThreshold else { return }
            hasDragged = true
            character.beginDrag(
                windowOriginAtDragStart: win.frame.origin,
                cursorScreenPos: mouseDownScreenPos
            )
        }

        character.continueDrag(cursorScreenPos: currentScreenPos)
    }

    override func mouseUp(with event: NSEvent) {
        if hasDragged, let character = character {
            // We need dockTopY to compute the landing Y.
            // Read it from the screen the window is currently on.
            let screen = window?.screen ?? NSScreen.main
            let dockTopY = screen?.visibleFrame.origin.y ?? 0
            character.endDrag(dockTopY: dockTopY)
        } else {
            // Short tap with no drag → treat as click
            character?.handleClick()
        }
        hasDragged = false
    }
}
