import Foundation
import CoreGraphics
import AppKit

func runDockVisibilityTests() {

    let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    expect(
        DockVisibility.shouldShowCharacters(
            screenFrame: screenFrame,
            visibleFrame: CGRect(x: 0, y: 64, width: 1440, height: 811),
            isMainScreen: true,
            dockAutohideEnabled: false
        ),
        "shows characters when the bottom dock reserves screen space"
    )

    expect(
        DockVisibility.shouldShowCharacters(
            screenFrame: screenFrame,
            visibleFrame: CGRect(x: 96, y: 0, width: 1344, height: 875),
            isMainScreen: true,
            dockAutohideEnabled: false
        ),
        "shows characters when the dock is pinned to the left edge"
    )

    expect(
        DockVisibility.shouldShowCharacters(
            screenFrame: screenFrame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1344, height: 875),
            isMainScreen: true,
            dockAutohideEnabled: false
        ),
        "shows characters when the dock is pinned to the right edge"
    )

    expect(
        !DockVisibility.shouldShowCharacters(
            screenFrame: screenFrame,
            visibleFrame: screenFrame,
            isMainScreen: true,
            dockAutohideEnabled: false
        ),
        "hides characters in fullscreen spaces where neither dock nor menu bar is visible"
    )

    expect(
        DockVisibility.shouldShowCharacters(
            screenFrame: screenFrame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            isMainScreen: true,
            dockAutohideEnabled: true
        ),
        "shows characters on the main screen when the dock auto-hides but the menu bar is visible"
    )

    expect(
        !DockVisibility.shouldShowCharacters(
            screenFrame: screenFrame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            isMainScreen: false,
            dockAutohideEnabled: true
        ),
        "keeps characters hidden on non-main screens when only the menu bar is visible"
    )

    expect(
        DockVisibility.collectionBehavior(showOnAllDesktops: false) == [.moveToActiveSpace, .stationary],
        "uses active-space behavior when show on all desktops is off"
    )

    expect(
        DockVisibility.collectionBehavior(showOnAllDesktops: true) == [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
        "uses all-spaces behavior when show on all desktops is on"
    )

    print("DockVisibility tests passed")
}
