import Foundation
import Security

actor KeychainService {
    static let shared = KeychainService()
    private let serviceName = "com.sovereign.deepseek"
    private let accountKey = "deepseek_api_key"

    private init() {}

    // MARK: - API Key

    func saveAPIKey(_ key: String) throws {
        guard !key.isEmpty else {
            try deleteAPIKey()
            return
        }

        let data = Data(key.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: Int(status))
        }
    }

    func getAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.readFailed(status: Int(status))
        }

        return key
    }

    func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: Int(status))
        }
    }

    func hasAPIKey() async -> Bool {
        (try? await getAPIKey()) != nil
    }

    // MARK: - Generic

    func saveGeneric(key: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: Int(status))
        }
    }

    func getGeneric(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.readFailed(status: Int(status))
        }
        return String(data: data, encoding: .utf8)
    }

    func deleteGeneric(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: Int(status))
        }
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(status: Int)
    case readFailed(status: Int)
    case deleteFailed(status: Int)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): return "Keychain 保存失败 (OSStatus: \(s))"
        case .readFailed(let s): return "Keychain 读取失败 (OSStatus: \(s))"
        case .deleteFailed(let s): return "Keychain 删除失败 (OSStatus: \(s))"
        }
    }
}

// MARK: - API Key Resolver (tries env var first, then Keychain)

func resolveAPIKey() async throws -> String? {
    if let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !envKey.isEmpty {
        return envKey
    }
    return try await KeychainService.shared.getAPIKey()
}
