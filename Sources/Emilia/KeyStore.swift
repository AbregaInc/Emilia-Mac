import Foundation
import Security

/// Credentials entered in the app use the standard macOS credential store.
enum KeyStore {
    private static let service = "com.abrega.emilia.openai"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "api-key"]
    }
    static func read() -> String {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String,
                     update: (CFDictionary, CFDictionary) -> OSStatus = SecItemUpdate,
                     add: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemAdd) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let status = update(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = add(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    private static func failure(_ status: OSStatus) -> NSError {
        NSError(domain: "Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Couldn’t securely save your API key. Please try again."])
    }
}
