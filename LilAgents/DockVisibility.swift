import AppKit
import CoreGraphics
import Foundation

enum AppPreferences {
    static let showOnAllDesktopsKey = "showOnAllDesktops"

    static var showOnAllDesktops: Bool {
        get {
            UserDefaults.standard.bool(forKey: showOnAllDesktopsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showOnAllDesktopsKey)
        }
    }
}

enum DockVisibility {
    static func collectionBehavior(showOnAllDesktops: Bool = AppPreferences.showOnAllDesktops) -> NSWindow.CollectionBehavior {
        showOnAllDesktops
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            : [.moveToActiveSpace, .stationary]
    }

    static func screenHasVisibleDockReservedArea(
        screenFrame: CGRect,
        visibleFrame: CGRect
    ) -> Bool {
        visibleFrame.minX > screenFrame.minX ||
        visibleFrame.minY > screenFrame.minY ||
        visibleFrame.maxX < screenFrame.maxX
    }

    static func shouldShowCharacters(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        isMainScreen: Bool,
        dockAutohideEnabled: Bool
    ) -> Bool {
        if screenHasVisibleDockReservedArea(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        ) {
            return true
        }

        let menuBarVisible = visibleFrame.maxY < screenFrame.maxY
        return dockAutohideEnabled && isMainScreen && menuBarVisible
    }
}
