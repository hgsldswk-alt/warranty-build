import Foundation
import Security

enum TrialAnchor {
    static func firstOpen(_ fallback: Date) -> Date {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "TrialKeychainAccessGroup") as? String,
              !group.isEmpty else { return fallback }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Launch.appID + ".trial",
            kSecAttrAccount as String: "first-open",
            kSecAttrAccessGroup as String: group
        ]
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let timestamp = Double(String(decoding: data, as: UTF8.self)), timestamp.isFinite,
           timestamp > 0 {
            return min(fallback, Date(timeIntervalSince1970: timestamp))
        }
        if status == errSecItemNotFound {
            var item = identity
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            item[kSecValueData as String] = Data(String(fallback.timeIntervalSince1970).utf8)
            SecItemAdd(item as CFDictionary, nil)
        }
        return fallback
    }
}
