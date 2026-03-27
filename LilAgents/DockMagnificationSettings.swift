import Foundation

/// User defaults for dock-like idle shrink (menu bar: "Shrink when idle" + delay).
enum DockMagnificationSettings {
    private static let enabledKey = "dockShrinkWhenIdleEnabled"
    private static let idleSecondsKey = "dockShrinkIdleSeconds"

    static let idlePresetsSeconds: [Int] = [10, 15, 20, 30, 60]

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Delay after popover closes before shrinking (seconds).
    static var idleSeconds: TimeInterval {
        get {
            let v = UserDefaults.standard.integer(forKey: idleSecondsKey)
            if v <= 0 { return 20 }
            return TimeInterval(v)
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: idleSecondsKey)
        }
    }
}
