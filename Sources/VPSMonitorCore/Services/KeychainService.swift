import Foundation
import Security

public enum KeychainService {
    private static let service = "VPSMonitor.SSH"

    public struct KeychainError: LocalizedError {
        public let operation: String
        public let status: OSStatus

        public var errorDescription: String? {
            L10n.text(
                "Связка ключей macOS вернула ошибку \(status) при операции: \(operation).",
                "macOS Keychain returned error \(status) while trying to \(operation)."
            )
        }
    }

    // MARK: - Public API

    public static func savePassword(_ password: String, for id: UUID) throws {
        let data = Data(password.utf8)
        var query = base(for: id)
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError(operation: "replace password", status: deleteStatus)
        }
        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError(operation: "save password", status: addStatus)
        }
    }

    public static func loadPassword(for id: UUID) -> String? {
        var query = base(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func deletePassword(for id: UUID) throws {
        let status = SecItemDelete(base(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(operation: "delete password", status: status)
        }
    }

    // MARK: - Private

    private static func base(for id: UUID) -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
    }
}
