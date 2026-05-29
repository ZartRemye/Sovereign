import Foundation

// MARK: - AI Generation Settings

struct AIModelGenerationSettings: Codable, Equatable {
    var maxTokens: Int = 4096
    var temperature: Double = 0.4
    var topP: Double = 0.9
    var enableStreaming: Bool = false
    var autoContinueWhenTruncated: Bool = true

    static func load() -> AIModelGenerationSettings {
        let defaults = UserDefaults.standard
        return AIModelGenerationSettings(
            maxTokens: defaults.integer(forKey: "ai_max_tokens") > 0 ? defaults.integer(forKey: "ai_max_tokens") : 4096,
            temperature: defaults.double(forKey: "ai_temperature") > 0 ? defaults.double(forKey: "ai_temperature") : 0.4,
            topP: defaults.double(forKey: "ai_top_p") > 0 ? defaults.double(forKey: "ai_top_p") : 0.9,
            enableStreaming: defaults.bool(forKey: "ai_streaming"),
            autoContinueWhenTruncated: defaults.bool(forKey: "ai_auto_continue")
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(maxTokens, forKey: "ai_max_tokens")
        d.set(temperature, forKey: "ai_temperature")
        d.set(topP, forKey: "ai_top_p")
        d.set(enableStreaming, forKey: "ai_streaming")
        d.set(autoContinueWhenTruncated, forKey: "ai_auto_continue")
    }
}

// MARK: - DeepSeek Response Result

struct DeepSeekChatResult {
    let content: String
    let finishReason: String?
    let promptTokens: Int?
    let completionTokens: Int?
    let isTruncated: Bool
    let totalTokens: Int?
}

// MARK: - DeepSeek Client

actor DeepSeekClient {
    static let shared = DeepSeekClient()

    private let defaultBaseURL = "https://api.deepseek.com"
    private let defaultModel = "deepseek-v4-pro"
    private let timeoutSeconds: Double = 120

    private var baseURL: String { UserDefaults.standard.string(forKey: "deepseek_base_url") ?? defaultBaseURL }
    private var model: String { UserDefaults.standard.string(forKey: "deepseek_model") ?? defaultModel }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Chat Completion (returns full result with finish_reason)

    func chat(systemPrompt: String, userMessage: String, settings: AIModelGenerationSettings? = nil) async throws -> DeepSeekChatResult {
        let apiKey = try await resolveAPIKey()
        guard let key = apiKey, !key.isEmpty else { throw DeepSeekError.noAPIKey }

        let genSettings = settings ?? AIModelGenerationSettings.load()

        let request = DeepSeekRequest(
            model: model,
            messages: [
                DeepSeekMessage(role: "system", content: systemPrompt),
                DeepSeekMessage(role: "user", content: userMessage),
            ],
            stream: false,
            temperature: genSettings.temperature,
            maxTokens: genSettings.maxTokens
        )

        let url = URL(string: "\(baseURL)/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = timeoutSeconds

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .timedOut {
            throw DeepSeekError.timeout
        } catch {
            throw DeepSeekError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }
        if httpResponse.statusCode == 429 { throw DeepSeekError.rateLimited }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw DeepSeekError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        let decoder = JSONDecoder()
        let result: DeepSeekResponse
        do {
            result = try decoder.decode(DeepSeekResponse.self, from: data)
        } catch {
            throw DeepSeekError.decodingError(error.localizedDescription)
        }

        guard let choice = result.choices.first else { throw DeepSeekError.invalidResponse }
        let content = choice.message.content
        let finishReason = choice.finishReason
        let isTruncated = finishReason == "length" || finishReason == "max_tokens"

        return DeepSeekChatResult(
            content: content,
            finishReason: finishReason,
            promptTokens: result.usage?.promptTokens,
            completionTokens: result.usage?.completionTokens,
            isTruncated: isTruncated,
            totalTokens: result.usage?.totalTokens
        )
    }

    // MARK: - Continuation (for truncated responses)

    func continueCompletion(
        systemPrompt: String,
        originalQuestion: String,
        previousAnswer: String,
        settings: AIModelGenerationSettings? = nil
    ) async throws -> DeepSeekChatResult {
        let continuationPrompt = """
        你刚才的回答因为长度限制被截断。请从中断处继续完成，不要重复已经写过的内容。保持同样的结构和语气。不要重新开头，直接从断开处接着写。

        原始问题：\(originalQuestion)

        已生成的回答（截断处）：
        \(previousAnswer.suffix(500))

        请继续完成剩余内容：
        """

        return try await chat(systemPrompt: systemPrompt, userMessage: continuationPrompt, settings: settings)
    }

    // MARK: - Connection Test

    func testConnection() async throws -> Bool {
        let apiKey = try await resolveAPIKey()
        guard let key = apiKey, !key.isEmpty else { throw DeepSeekError.noAPIKey }
        let request = DeepSeekRequest(model: model, messages: [DeepSeekMessage(role: "user", content: "Hi")], stream: false, temperature: 0, maxTokens: 10)
        let url = URL(string: "\(baseURL)/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 15
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (_, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw DeepSeekError.invalidResponse }
        return (200...299).contains(httpResponse.statusCode)
    }
}
