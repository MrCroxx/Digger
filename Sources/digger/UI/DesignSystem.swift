import SwiftUI

/// Adaptive colors for native macOS surfaces. Popup spacing is intentionally independent of settings.
enum DiggerTheme {
    static let ink = adaptive(0x302720, 0xeee5dc)
    static let muted = adaptive(0x796c60, 0xb6a698)
    static let line = adaptive(0xe4dacf, 0x44372e)
    static let paper = adaptive(0xfffcf7, 0x261f1a)
    static let canvas = adaptive(0xf4efe8, 0x191410)
    static let sidebar = adaptive(0xfaf6f0, 0x201914)
    static let accent = adaptive(0x805538, 0xd1a37a)
    static let soft = adaptive(0xeee2d5, 0x3a2a1f)
    static let brand = Color(red: 128 / 255, green: 85 / 255, blue: 56 / 255)
    static let brandInk = Color(red: 1, green: 248 / 255, blue: 237 / 255)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

func localized(_ english: String, _ chinese: String, _ japanese: String) -> String {
    switch AppPreferences.language() {
    case .english: english
    case .chineseSimplified: chinese
    case .japanese: japanese
    }
}

struct BrandMark: View {
    var size: CGFloat = 34
    var body: some View {
        Text("d").font(.system(size: size * 0.76, weight: .medium, design: .serif))
            .foregroundStyle(DiggerTheme.brandInk)
            .frame(width: size, height: size)
            .background(DiggerTheme.brand, in: RoundedRectangle(cornerRadius: size * 0.27))
            .accessibilityHidden(true)
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(DiggerTheme.paper, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DiggerTheme.line, lineWidth: 1))
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(7)
            .background(configuration.isPressed ? DiggerTheme.soft : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
    }
}
