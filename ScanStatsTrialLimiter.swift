import Foundation
import Security

@MainActor
enum ScanStatsTrialLimiter {

    private static let service = "com.boxverify.app.scanstats.trial"
    private static let account = "free_preview_count"
    private static let maxPreviewCount = 5

    static func previewCount() -> Int {
        guard let data = readData(),
              let string = String(data: data, encoding: .utf8),
              let value = Int(string) else {
            return 0
        }
        return max(0, min(value, maxPreviewCount))
    }

    static func canShowPreview() -> Bool {
        previewCount() < maxPreviewCount
    }

    @discardableResult
    static func recordPreviewUse() -> Int {
        let next = min(previewCount() + 1, maxPreviewCount)
        writeData(Data("\(next)".utf8))
        return next
    }

    static func remainingPreviewCount() -> Int {
        max(0, maxPreviewCount - previewCount())
    }

    static func hasReachedLimit() -> Bool {
        previewCount() >= maxPreviewCount
    }

    // MARK: - Keychain

    private static func readData() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func writeData(_ data: Data) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            let addQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
