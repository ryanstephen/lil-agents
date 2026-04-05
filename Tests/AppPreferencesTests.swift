import Foundation

func runAppPreferencesTests() {
    let defaults = UserDefaults.standard
    let key = AppPreferences.showOnAllDesktopsKey
    let originalValue = defaults.object(forKey: key)

    defer {
        defaults.removeObject(forKey: key)
        if let originalValue {
            defaults.set(originalValue, forKey: key)
        }
    }

    defaults.removeObject(forKey: key)
    expect(AppPreferences.showOnAllDesktops == false, "show on all desktops defaults to off")

    AppPreferences.showOnAllDesktops = true
    expect(defaults.bool(forKey: key) == true, "show on all desktops persists on")

    print("AppPreferences tests passed")
}
