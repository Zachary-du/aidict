import Foundation
import AppKit
import ApplicationServices

public enum Permissions {
    public static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public static func ensureAccessibility(forcePrompt: Bool = false) {
        if !isAccessibilityTrusted() {
            let hasPrompted = UserDefaults.standard.bool(forKey: "has_prompted_accessibility_v2")
            if !hasPrompted || forcePrompt {
                UserDefaults.standard.set(true, forKey: "has_prompted_accessibility_v2")
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                AXIsProcessTrustedWithOptions(options)
            }
        }
    }
}
