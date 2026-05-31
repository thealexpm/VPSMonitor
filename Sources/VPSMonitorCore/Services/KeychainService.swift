import Foundation
import Security

public enum KeychainService {
    private static let service = "VPSMonitor.SSH"

    // MARK: - Public API

    public static func savePassword(_ password: String, for id: UUID) {
        let data = Data(password.utf8)
        var query = base(for: id)
        SecItemDelete(query as CFDictionary)          // remove old entry if exists
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
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

    public static func deletePassword(for id: UUID) {
        SecItemDelete(base(for: id) as CFDictionary)
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
