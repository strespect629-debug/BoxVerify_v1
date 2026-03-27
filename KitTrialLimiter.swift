import Foundation
import Security

@MainActor
enum KitTrialLimiter {

    private static let service = "com.boxverify.app.kittrial"
    private static let account = "one_time_result_reveal"

    static func canRevealFirstResult() -> Bool {
        return !hasConsumedOneTimeReveal()
    }

    @discardableResult
    static func consumeOneTimeReveal() -> Bool {
        if hasConsumedOneTimeReveal() { return false }

        let data = Data("consumed".utf8)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func hasConsumedOneTimeReveal() -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: false,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
