import Foundation

/// User preferences, stored in UserDefaults.
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    /// Apps where typing is left alone (terminals and code editors).
    static let defaultExcluded: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.microsoft.VSCode",
        "com.apple.dt.Xcode",
    ]

    /// Master switch: suggestions and corrections.
    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    /// When off, the strip still shows suggestions but nothing is replaced on space.
    var autocorrect: Bool {
        get { defaults.object(forKey: "autocorrect") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autocorrect") }
    }

    /// Draws the notch "wings" layout even on Macs without a notch, around a fake one.
    var previewNotch: Bool {
        get { defaults.bool(forKey: "previewNotch") }
        set { defaults.set(newValue, forKey: "previewNotch") }
    }

    var excludedBundleIDs: Set<String> {
        get {
            guard let list = defaults.array(forKey: "excluded") as? [String] else { return Settings.defaultExcluded }
            return Set(list)
        }
        set { defaults.set(Array(newValue), forKey: "excluded") }
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    func setExcluded(_ bundleID: String, _ excluded: Bool) {
        var set = excludedBundleIDs
        if excluded { set.insert(bundleID) } else { set.remove(bundleID) }
        excludedBundleIDs = set
    }
}
