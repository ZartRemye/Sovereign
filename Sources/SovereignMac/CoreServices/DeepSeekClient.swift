import Foundation

actor DeepSeekClient {
    static let shared = DeepSeekClient()

    private let defaultBaseURL = "https://api.deepseek.com"
    private let defaultModel = "deepseek-v4-pro"
    private let timeoutSeconds: Double = 30

    private var baseURL: String { UserDefaults.standard.string(forKey: "deepseek_base_url") ?? defaultBaseURL }
    private var model: String { UserDefaults.standard.string(forKey: "deepseek_model") ?? defaultModel }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Chat Completion (non-streaming)

    func chat(systemPrompt: String, userMessage: String) async throws -> String {
        let apiKey = try await resolveAPIKey()
        guard let key = apiKey, !key.isEmpty else {
            throw DeepSeekError.noAPIKey
        }

        let request = DeepSeekRequest(
            model: model,
            messages: [
                DeepSeekMessage(role: "system", content: systemPrompt),
                DeepSeekMessage(role: "user", content: userMessage),
            ],
            stream: false,
            temperature: 0.7,
            maxTokens: 800
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

        if httpResponse.statusCode == 429 {
            throw DeepSeekError.rateLimited
        }

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

        guard let content = result.choices.first?.message.content, !content.isEmpty else {
            throw DeepSeekError.invalidResponse
        }

        return content
    }

    // MARK: - Connection Test

    func testConnection() async throws -> Bool {
        let apiKey = try await resolveAPIKey()
        guard let key = apiKey, !key.isEmpty else {
            throw DeepSeekError.noAPIKey
        }

        let request = DeepSeekRequest(
            model: model,
            messages: [
                DeepSeekMessage(role: "user", content: "Hello"),
            ],
            stream: false,
            temperature: 0,
            maxTokens: 10
        )

        let url = URL(string: "\(baseURL)/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 15

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (_, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }
        return (200...299).contains(httpResponse.statusCode)
    }
}

// MARK: - Future Streaming Interface (reserved)

protocol DeepSeekStreamingDelegate: AnyObject {
    func deepSeekClient(_ client: DeepSeekClient, didReceiveChunk text: String)
    func deepSeekClient(_ client: DeepSeekClient, didCompleteWith error: Error?)
}
