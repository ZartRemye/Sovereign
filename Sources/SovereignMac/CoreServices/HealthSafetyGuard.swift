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
    case abnormallyHighHR = "心率异常很高"
    case severeInjury = "严重受伤"
    case suddenHeadache = "突然剧烈头痛"
    case selfHarm = "自残"
    case suicide = "自杀"
    case extremeWeightLoss = "极端减脂"
    case overtraining = "过度训练"
    case medicationDosage = "药物剂量"
    case medicalDiagnosis = "医疗诊断请求"
}

struct HealthSafetyGuard {
    private static let safetyKeywords: [SafetyCategory: [String]] = [
        .chestPain: ["胸痛", "胸口疼", "心口痛", "chest pain", "心绞痛"],
        .syncope: ["晕厥", "晕倒", "昏倒", "syncope", "fainting", "失去意识", "昏厥"],
        .breathingDifficulty: ["呼吸困难", "喘不上气", "窒息", "shortness of breath", "breathing difficulty"],
        .severePalpitations: ["心悸", "心跳过快", "心慌", "严重心慌", "palpitations"],
        .abnormallyHighHR: ["心率超过200", "心率超过180", "心率异常高"],
        .severeInjury: ["重伤", "骨折", "大出血", "severe injury", "严重受伤"],
        .suddenHeadache: ["剧烈头痛", "突然头痛", "雷击样头痛", "thunderclap headache"],
        .selfHarm: ["自残", "割腕", "self harm", "伤害自己"],
        .suicide: ["自杀", "想死", "不想活", "suicide", "结束生命", "寻死"],
        .extremeWeightLoss: ["极端减脂", "暴瘦", "绝食", "催吐", "厌食"],
        .overtraining: ["过度训练到受伤", "训练到吐血", "每天训练6小时"],
        .medicationDosage: ["药量", "剂量", "吃什么药", "开药", "处方", "降压药", "该吃多少"],
        .medicalDiagnosis: ["诊断", "是不是得了", "什么病", "会不会是", "disease", "diagnose"],
    ]

    private static let genericSafetyWarning = """
        我不能根据 Apple Watch 数据为你做医疗诊断。你提到的情况可能需要专业判断。\
        如果你正在经历胸痛、晕厥、严重呼吸困难、持续异常心率等情况，请尽快联系医生或急救服务。

        我可以帮你分析健康数据中的趋势和模式，但这不能替代专业医疗意见。
        """

    private static let overtrainingWarning = """
        你的训练强度显示可能存在过度训练风险。建议你：
        1. 适当减少训练量和强度
        2. 确保充足的睡眠和营养摄入
        3. 关注身体的恢复信号
        这不是医疗诊断。如果感到持续不适，请咨询运动医学专家。
        """

    func check(_ input: String) -> SafetyCheckResult {
        let lowercased = input.lowercased()

        // Check highest-priority categories first
        let priorityCategories: [SafetyCategory] = [
            .suicide, .selfHarm, .chestPain, .syncope,
            .breathingDifficulty, .severeInjury, .suddenHeadache,
        ]

        for category in priorityCategories {
            if matchesCategory(category, in: lowercased) {
                return .blocked(category, message: Self.genericSafetyWarning)
            }
        }

        // Check medium-priority
        let mediumPriority: [SafetyCategory] = [
            .severePalpitations, .abnormallyHighHR,
            .medicationDosage, .medicalDiagnosis, .extremeWeightLoss,
        ]

        for category in mediumPriority {
            if matchesCategory(category, in: lowercased) {
                return .blocked(category, message: Self.genericSafetyWarning)
            }
        }

        // Overtraining - special handling with more specific advice
        if matchesCategory(.overtraining, in: lowercased) {
            return .blocked(.overtraining, message: Self.overtrainingWarning)
        }

        return .safe
    }

    private func matchesCategory(_ category: SafetyCategory, in text: String) -> Bool {
        guard let keywords = Self.safetyKeywords[category] else { return false }
        return keywords.contains { text.contains($0.lowercased()) }
    }
}
