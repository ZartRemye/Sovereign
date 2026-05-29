import Foundation
import UserNotifications

/// Manages local notification delivery for health alerts and summaries.
actor NotificationService {
    static let shared = NotificationService()

    private var notificationsEnabled = true
    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Setup

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            notificationsEnabled = granted
            return granted
        } catch {
            notificationsEnabled = false
            return false
        }
    }

    // MARK: - Send Notifications

    func sendAlert(_ alert: AlertRecord) async {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.message
        content.sound = .default
        content.categoryIdentifier = "HEALTH_ALERT"

        let request = UNNotificationRequest(
            identifier: alert.id.uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        try? await center.add(request)
    }

    func sendSleepDeprivationAlert(avgSleepHours: Double) async {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "睡眠不足提醒"
        content.body = "最近3天平均睡眠仅 \(String(format: "%.1f", avgSleepHours)) 小时。建议今晚提早休息。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "sleep_deprivation_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    func sendRecoveryLowAlert(score: Double) async {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "恢复评分偏低"
        content.body = "当前恢复评分为 \(String(format: "%.0f", score))/100。建议降低训练强度，保证充足休息。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "recovery_low_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    func sendTrainingLoadHighAlert(ratio: Double) async {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "训练负荷偏高"
        content.body = "近期训练负荷较之前显著增加 (ACWR: \(String(format: "%.2f", ratio)))。注意恢复。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "load_high_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    func sendInactivityAlert() async {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "活动提醒"
        content.body = "你最近活动量较低。即使短距离散步也对健康有益。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "inactivity_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    func sendAnalysisCompleteNotification(title: String, body: String) async {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "analysis_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    func sendAnalysisFailedNotification(error: Error) async {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "AI 分析失败"
        content.body = "DeepSeek 分析失败，已切换到本地规则。\(error.localizedDescription)"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "analysis_failed_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    // MARK: - Settings

    func setEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
    }
}
