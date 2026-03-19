import CryptoKit
import Foundation
import Security

enum KeychainManager {
    private static let service = "com.jot.app.noteLock"
    private static let account = "customPassword"

    @discardableResult
    static func savePassword(_ password: String) -> Bool {
        deletePassword()

        var saltBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        let salt = saltBytes.map { String(format: "%02x", $0) }.joined()

        let salted = salt + password
        let hash = SHA256.hash(data: Data(salted.utf8))
        let hashHex = hash.map { String(format: "%02x", $0) }.joined()
        let stored = "\(salt):\(hashHex)"

        guard let data = stored.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func verifyPassword(_ input: String, against stored: String) -> Bool {
        if stored.contains(":") {
            let parts = stored.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return false }
            let salt = String(parts[0])
            let expectedHash = String(parts[1])
            let salted = salt + input
            let hash = SHA256.hash(data: Data(salted.utf8))
            let hashHex = hash.map { String(format: "%02x", $0) }.joined()
            return hashHex == expectedHash
        } else {
            // Migration: old plaintext format
            return stored == input
        }
    }

    static func loadPassword() -> String? {
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
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func deletePassword() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
