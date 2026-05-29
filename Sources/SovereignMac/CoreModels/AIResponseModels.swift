import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    let contextSummary: String?
    let isFallback: Bool

    enum MessageRole: String, Codable {
        case user
        case assistant
        case system
    }

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(),
         contextSummary: String? = nil, isFallback: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.contextSummary = contextSummary
        self.isFallback = isFallback
    }
}

// MARK: - Health Context (sent to AI)

struct HealthContext: Codable {
    let generatedAt: Date
    let dataSource: String
    let isMockData: Bool
    let lastSyncDate: Date?

    let sevenDaySummary: SevenDaySummary
    let thirtyDaySummary: ThirtyDaySummary
    let recentWorkouts: [WorkoutSummary]
    let localInsights: [LocalInsight]
    let dataQuality: DataQualityInfo
}

struct SevenDaySummary: Codable {
    let dailySteps: [DailyValue]
    let dailySleep: [DailyValue]
    let dailyRestingHR: [DailyValue]
    let dailyExerciseMinutes: [DailyValue]
    let dailyActiveEnergy: [DailyValue]
    let dailyTrainingLoad: [DailyValue]
    let dailyRecoveryScore: [DailyValue]
}

struct ThirtyDaySummary: Codable {
    let avgSteps: Double
    let avgSleepHours: Double
    let avgRestingHR: Double
    let avgActiveEnergy: Double
    let workoutFrequency: Int
    let trainingLoadChange: String
    let recoveryTrend: String
}

struct DailyValue: Codable {
    let date: String
    let value: Double
}

struct WorkoutSummary: Codable {
    let type: String
    let date: String
    let durationMinutes: Int
    let distanceKm: Double?
    let avgHeartRate: Double?
    let intensityEstimate: String
}

struct LocalInsight: Codable {
    let title: String
    let message: String
    let severity: String
}

struct DataQualityInfo: Codable {
    let dateRangeStart: String
    let dateRangeEnd: String
    let missingMetrics: [String]
    let lastSyncDate: String?
    let isMockData: Bool
    let dataSource: String
}

// MARK: - AI Analysis Result

struct AIAnalysisResult: Codable {
    let content: String
    let model: String
    let tokensUsed: Int?
    let finishReason: String?
    let cachedAt: Date
}

// MARK: - DeepSeek API Models

struct DeepSeekRequest: Codable {
    let model: String
    let messages: [DeepSeekMessage]
    let stream: Bool
    let temperature: Double?
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens = "max_tokens"
    }
}

struct DeepSeekMessage: Codable {
    let role: String
    let content: String
}

struct DeepSeekResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [DeepSeekChoice]
    let usage: DeepSeekUsage?
}

struct DeepSeekChoice: Codable {
    let index: Int
    let message: DeepSeekMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct DeepSeekUsage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - API Error

enum DeepSeekError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case decodingError(String)
    case noAPIKey
    case timeout
    case networkError(Error)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 API 地址"
        case .invalidResponse: return "无法解析服务器响应"
        case .httpError(let code, _): return "HTTP 错误 \(code)"
        case .decodingError(let detail): return "响应解析失败: \(detail)"
        case .noAPIKey: return "未配置 API Key"
        case .timeout: return "请求超时"
        case .networkError(let err): return "网络错误: \(err.localizedDescription)"
        case .rateLimited: return "请求过于频繁，请稍后再试"
        }
    }
}

// MARK: - Import Result

enum ImportResult {
    case success(ImportSummary)
    case partial(ImportSummary, [ImportError])
    case failure(ImportError)
}

struct ImportSummary {
    let metricSamples: Int
    let workoutSessions: Int
    let sleepSessions: Int
    let dateRange: (start: Date, end: Date)?
    let fileName: String
}

struct ImportError: LocalizedError {
    let message: String
    let underlyingError: Error?

    var errorDescription: String? { message }
}

// MARK: - Report

struct HealthReport: Identifiable {
    let id: UUID
    let type: ReportType
    let title: String
    let content: String
    let generatedAt: Date
    let dateRange: (start: Date, end: Date)
    let source: String

    enum ReportType: String, Codable {
        case daily = "日报"
        case weekly = "周报"
        case monthly = "月报"
    }

    var markdownContent: String {
        """
        # \(title)
        **生成时间**: \(formattedDate)
        **数据来源**: \(source)

        ---
        \(content)

        ---
        > **免责声明**: Sovereign 不是医疗设备，不提供医疗诊断。本报告仅供参考。如有健康疑虑，请咨询医生。
        """
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: generatedAt)
    }
}

// MARK: - Sync Envelope (future iPhone/Watch sync)

struct SyncEnvelope: Codable {
    let source: String
    let deviceName: String
    let timestamp: Date
    let metrics: [LiveMetricEvent]
    let workouts: [WorkoutSyncData]
    let sleepSessions: [SleepSyncData]
}

struct LiveMetricEvent: Codable {
    let type: String
    let value: Double
    let unit: String
    let timestamp: Date
}

struct WorkoutSyncData: Codable {
    let type: String
    let startDate: Date
    let endDate: Date
    let durationSeconds: Double
    let distanceMeters: Double?
    let avgHeartRate: Double?
    let maxHeartRate: Double?
    let activeEnergyKJ: Double?
}

struct SleepSyncData: Codable {
    let startDate: Date
    let endDate: Date
    let durationSeconds: Double
    let deepSleepSeconds: Double?
    let remSleepSeconds: Double?
}

// MARK: - App Settings

struct AISettings {
    var deepSeekEnabled: Bool = false
    var modelName: String = "deepseek-v4-pro"
    var baseURL: String = "https://api.deepseek.com"
    var allowCloudSummary: Bool = false
    var currentMode: String = "Local Rules"
}

struct AnalysisSettings {
    var backgroundAnalysisEnabled: Bool = true
    var analysisIntervalMinutes: Int = 15
    var notificationsEnabled: Bool = true
    var useMockLiveData: Bool = true
    var autoGenerateDailyReport: Bool = true
    var autoGenerateWeeklyReport: Bool = false
}
