import Foundation
import Security

/// Despite the name (kept to avoid touching call sites), this no longer uses the
/// macOS Keychain: a Keychain item's access is tied to the app's code signature,
/// and this app is ad-hoc signed — every rebuild changes that signature, so macOS
/// silently denies access to the previously saved item and the setup sheet
/// reappears on every restart. UserDefaults has no such gate.
enum KeychainStore {
    private static let defaultsKey = "usageConfig"
    private static let legacyService = "com.ngoujon.claudeusagedashboard"
    private static let legacyAccount = "usage-config"

    struct Config: Codable {
        let usageURL: String
        let cookie: String
    }

    static func load() -> Config? {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config
        }
        if let migrated = loadLegacyKeychainValue() {
            save(migrated)
            return migrated
        }
        return nil
    }

    static func save(_ config: Config) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private static func loadLegacyKeychainValue() -> Config? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: legacyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }
}
