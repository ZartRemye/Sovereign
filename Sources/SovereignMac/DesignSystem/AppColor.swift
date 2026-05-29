import SwiftUI

enum AppColor {
    // Primary palette
    static let primary = Color.accentColor
    static let primaryMuted = Color.accentColor.opacity(0.6)

    // Semantic colors
    static let recoveryGood = Color.green
    static let recoveryModerate = Color.orange
    static let recoveryPoor = Color.red
    static let sleepGood = Color.indigo
    static let stepsGood = Color.mint
    static let hrNormal = Color.teal
    static let hrWarning = Color.orange
    static let hrDanger = Color.red
    static let insight = Color.blue
    static let insightPositive = Color.green
    static let insightWarning = Color.orange
    static let insightCritical = Color.red

    // Cards & surfaces
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let glassBackground = Color(nsColor: .controlBackgroundColor).opacity(0.7)

    // Charts
    static let chartLine = Color.accentColor
    static let chartFill = Color.accentColor.opacity(0.15)
    static let chartSecondary = Color.secondary
}
