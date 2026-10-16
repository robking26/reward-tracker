import Foundation
import Security

/// Minimal Keychain wrapper for secrets such as the Starling token.
/// Items are device-only and never synced to iCloud.
enum Keychain {
    enum Item: String {
        case starlingSandboxToken = "starling.token.sandbox"
        case starlingProductionToken = "starling.token.production"

        static func starlingToken(for environment: BankingEnvironment) -> Item {
            environment == .sandbox ? .starlingSandboxToken : .starlingProductionToken
        }
    }

    private static let service = "com.robking.FitnessVault"

    static func read(_ item: Item) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String, for item: Item) -> Bool {
        delete(item)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ item: Item) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
