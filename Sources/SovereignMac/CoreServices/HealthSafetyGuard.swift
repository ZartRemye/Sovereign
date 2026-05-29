import Foundation

struct SafetyCheckResult {
    let isSafe: Bool
    let category: SafetyCategory?
    let warningMessage: String?

    static let safe = SafetyCheckResult(isSafe: true, category: nil, warningMessage: nil)

    static func blocked(_ category: SafetyCategory, message: String) -> SafetyCheckResult {
        SafetyCheckResult(isSafe: false, category: category, warningMessage: message)
    }
}

enum SafetyCategory: String, CaseIterable {
    case chestPain = "胸痛"
    case syncope = "晕厥"
    case breathingDifficulty = "呼吸困难"
    case severePalpitations = "严重心悸"
    case severeInjury = "严重受伤"
    case suddenHeadache = "突然剧烈头痛"
    case selfHarm = "自残"
    case suicide = "自杀"
    case medicationDosage = "药物剂量"
    case medicalDiagnosis = "明确医疗诊断请求"
}

/// HealthSafetyGuard only blocks HIGH-RISK content that genuinely needs medical attention.
/// Normal training, sleep, fatigue, weight loss questions are NOT blocked — they get data-driven analysis.
struct HealthSafetyGuard {

    // Only truly high-risk keywords — does NOT include normal training/fatigue/diet questions
    private static let highRiskKeywords: [SafetyCategory: [String]] = [
        .chestPain: ["胸痛", "胸口疼", "心口痛", "chest pain", "心绞痛", "胸口闷痛"],
        .syncope: ["晕厥", "晕倒", "昏倒", "syncope", "fainting", "失去意识", "昏厥", "突然晕"],
        .breathingDifficulty: ["呼吸困难", "喘不上气", "窒息", "shortness of breath", "breathing difficulty", "喘不过气"],
        .severePalpitations: ["严重心悸", "心跳过速", "心跳200", "心跳异常快", "心慌到不行"],
        .severeInjury: ["重伤", "骨折", "大出血", "severe injury", "严重受伤", "断骨"],
        .suddenHeadache: ["剧烈头痛", "突然剧烈头痛", "雷击样头痛", "thunderclap headache", "头痛欲裂"],
        .selfHarm: ["自残", "割腕", "self harm", "伤害自己", "自伤"],
        .suicide: ["自杀", "想死", "不想活", "suicide", "结束生命", "寻死", "不想活了"],
        .medicationDosage: ["该吃多少药", "药量多少", "开什么药", "处方药", "降压药剂量", "吃什么药能治"],
        .medicalDiagnosis: ["是不是得了心脏病", "是不是得了癌症", "诊断一下", "我得了什么病"],
    ]

    private static let emergencyWarning = """
        ⚠️ 你提到的情况可能涉及需要紧急医疗关注的健康问题。

        我不能根据 Apple Watch 数据做医疗判断。如果你正经受胸痛、晕厥、严重呼吸困难、持续异常心率等症状，请立即联系医生或拨打急救电话。

        Sovereign 只能分析健康数据中的趋势和模式，不能替代专业医疗意见。
        """

    func check(_ input: String) -> SafetyCheckResult {
        let lowercased = input.lowercased()

        // Only check truly high-risk categories
        let priorityCategories: [SafetyCategory] = [
            .suicide, .selfHarm, .chestPain, .syncope,
            .breathingDifficulty, .severeInjury, .suddenHeadache,
        ]

        for category in priorityCategories {
            if matchesCategory(category, in: lowercased) {
                return .blocked(category, message: Self.emergencyWarning)
            }
        }

        // Medication and diagnosis — only if explicitly asking for medical advice
        let secondaryCategories: [SafetyCategory] = [
            .medicationDosage, .medicalDiagnosis,
        ]

        for category in secondaryCategories {
            if matchesCategory(category, in: lowercased) {
                return .blocked(category, message: "我无法提供药物或医疗诊断建议。如果你有健康疑虑，建议咨询医生。我可以帮你分析健康数据趋势，但这不是医疗建议。")
            }
        }

        // Everything else is safe — training, sleep, fatigue, weight management, etc.
        return .safe
    }

    private func matchesCategory(_ category: SafetyCategory, in text: String) -> Bool {
        guard let keywords = Self.highRiskKeywords[category] else { return false }
        return keywords.contains { text.contains($0.lowercased()) }
    }
}
