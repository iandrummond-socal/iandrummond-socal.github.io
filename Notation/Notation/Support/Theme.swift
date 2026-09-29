import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }
}

/// A tool, not a brand: warm off-white paper, near-black ink, one quiet gray for selection.
enum Theme {
    static let uiBackground = UIColor.dynamic(light: 0xF4F1EA, dark: 0x141311)
    static let uiField = UIColor.dynamic(light: 0xFBFAF7, dark: 0x1C1B19)
    static let uiText = UIColor.dynamic(light: 0x1C1B19, dark: 0xE7E2D6)
    static let uiSecondary = UIColor.dynamic(light: 0x8A847A, dark: 0x8A847A)
    static let uiSelection = UIColor.dynamic(light: 0xE4DFD3, dark: 0x2A2825)
    static let uiRule = UIColor.dynamic(light: 0xDDD8CC, dark: 0x2A2825)

    static let background = Color(uiBackground)
    static let field = Color(uiField)
    static let text = Color(uiText)
    static let secondary = Color(uiSecondary)
    static let selection = Color(uiSelection)
    static let rule = Color(uiRule)

    static let bodyLineHeightMultiple: CGFloat = 1.35
}
