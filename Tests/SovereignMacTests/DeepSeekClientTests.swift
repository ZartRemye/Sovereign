import XCTest
@testable import Sovereign

final class DeepSeekClientTests: XCTestCase {
    func testRequestEncoding() throws {
        let request = DeepSeekRequest(
            model: "deepseek-v4-pro",
            messages: [
                DeepSeekMessage(role: "system", content: "You are a health assistant."),
                DeepSeekMessage(role: "user", content: "How am I doing today?"),
            ],
            stream: false,
            temperature: 0.7,
            maxTokens: 800
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(dict?["model"] as? String, "deepseek-v4-pro")
        XCTAssertEqual(dict?["stream"] as? Bool, false)
        XCTAssertEqual(dict?["temperature"] as? Double, 0.7)
        XCTAssertEqual(dict?["max_tokens"] as? Int, 800)

        let messages = dict?["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?[0]["role"] as? String, "system")
    }

    func testResponseDecoding() throws {
        let json = """
        {
            "id": "chatcmpl-123",
            "object": "chat.completion",
            "created": 1677652288,
            "model": "deepseek-v4-pro",
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": "Based on your health data, you're doing well."
                    },
                    "finish_reason": "stop"
                }
            ],
            "usage": {
                "prompt_tokens": 50,
                "completion_tokens": 20,
                "total_tokens": 70
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(DeepSeekResponse.self, from: json)

        XCTAssertEqual(response.model, "deepseek-v4-pro")
        XCTAssertEqual(response.choices.first?.message.content, "Based on your health data, you're doing well.")
        XCTAssertEqual(response.choices.first?.finishReason, "stop")
        XCTAssertEqual(response.usage?.totalTokens, 70)
    }

    func testDeepSeekErrorDescriptions() {
        XCTAssertNotNil(DeepSeekError.noAPIKey.errorDescription)
        XCTAssertNotNil(DeepSeekError.invalidURL.errorDescription)
        XCTAssertNotNil(DeepSeekError.timeout.errorDescription)
        XCTAssertNotNil(DeepSeekError.rateLimited.errorDescription)
    }

    func testChatMessageEquality() {
        let id = UUID()
        let now = Date()
        let m1 = ChatMessage(id: id, role: .user, content: "Hello", timestamp: now)
        let m2 = ChatMessage(id: id, role: .user, content: "Hello", timestamp: now)
        XCTAssertEqual(m1, m2)

        let m3 = ChatMessage(id: id, role: .user, content: "Different", timestamp: now)
        XCTAssertNotEqual(m1, m3)
    }
}
