import Foundation
import Security

enum KeychainStore {
    private static let service = "com.ngoujon.claudeusagedashboard"
    private static let account = "usage-config"

    struct Config: Codable {
        let usageURL: String
        let cookie: String
    }

    static func load() -> Config? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    static func save(_ config: Config) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
