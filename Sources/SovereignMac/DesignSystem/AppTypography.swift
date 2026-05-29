import SwiftUI

enum AppTypography {
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title = Font.title.weight(.semibold)
    static let title2 = Font.title2.weight(.medium)
    static let title3 = Font.title3.weight(.medium)
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let caption = Font.caption
    static let caption2 = Font.caption2

    // Metric values
    static let metricValue = Font.system(size: 32, weight: .bold, design: .rounded)
    static let metricUnit = Font.system(size: 14, weight: .medium, design: .rounded)
    static let metricLabel = Font.caption.weight(.medium)

    // Score displays
    static let scoreLarge = Font.system(size: 48, weight: .bold, design: .rounded)
}
