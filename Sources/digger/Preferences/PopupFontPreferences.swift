import CoreGraphics
import Foundation

enum PopupFontPreferences {
    static let key = "PopupFontSize"
    static let defaultSize: CGFloat = 12
    static let minSize: CGFloat = 10
    static let maxSize: CGFloat = 20

    static func load() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: key)
        if stored <= 0 {
            return defaultSize
        }
        return clamp(CGFloat(stored))
    }

    static func save(_ size: CGFloat) {
        UserDefaults.standard.set(Double(clamp(size)), forKey: key)
    }

    static func clamp(_ size: CGFloat) -> CGFloat {
        let rounded = size.rounded()
        return min(max(rounded, minSize), maxSize)
    }

    static func format(_ size: CGFloat) -> String {
        "\(Int(size.rounded())) pt"
    }
}
