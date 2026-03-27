import Foundation
import Security

// =====================================================
// MARK: - RealtimeTrialLimiter（Keychain / Tokyo day）
// - 無課金：1回=1スキャン判定 を 1日1回まで
// - 上限到達後は当日中、判定を出さない（Base Codeも強制解除）
// =====================================================

enum RealtimeTrialLimiter {

    static let maxPerDay: Int = 1

    struct Status: Equatable {
        let dayKey: String          // "yyyy-MM-dd" (Asia/Tokyo)
        let used: Int               // 0...max
        var remaining: Int { max(0, maxPerDay - used) }
        var isExhausted: Bool { used >= maxPerDay }
    }

    // MARK: Public

    static func status() -> Status {
        resetIfNewDay()
        let day = tokyoDayKey()
        let used = readUsedCount(for: day)
        return Status(dayKey: day, used: used)
    }

    static func resetIfNewDay() {
        let today = tokyoDayKey()
        let storedDay = readStoredDayKey()

        if storedDay != today {
            // ✅ Keychain肥大化防止：前日の used.* を削除（最大1日分だけ保持）
            if let storedDay {
                deleteItem(account: accountUsedKey(for: storedDay))
            }

            writeStoredDayKey(today)
            writeUsedCount(0, for: today)
        } else {
            _ = readUsedCount(for: today) // ensure exists
        }
    }

    @discardableResult
    static func recordAttempt() -> Bool {
        resetIfNewDay()
        let day = tokyoDayKey()
        let used = readUsedCount(for: day)
        guard used < maxPerDay else { return false }
        writeUsedCount(used + 1, for: day)
        return true
    }

    // MARK: - Keychain storage

    private static let service = "app.boxverify.realtimeTrial"
    private static let accountDayKey = "dayKey"
    private static func accountUsedKey(for dayKey: String) -> String { "used.\(dayKey)" }

    private static func readStoredDayKey() -> String? {
        readString(account: accountDayKey)
    }

    private static func writeStoredDayKey(_ value: String) {
        writeString(value, account: accountDayKey)
    }

    private static func readUsedCount(for dayKey: String) -> Int {
        let account = accountUsedKey(for: dayKey)
        if let s = readString(account: account), let n = Int(s) {
            return max(0, n)
        }
        writeUsedCount(0, for: dayKey)
        return 0
    }

    private static func writeUsedCount(_ value: Int, for dayKey: String) {
        let account = accountUsedKey(for: dayKey)
        writeString(String(max(0, value)), account: account)
    }

    private static func writeString(_ value: String, account: String) {
        let data = Data(value.utf8)

        // update if exists, else add
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // ✅ 端末限定（バックアップ/移行でのズレ事故を減らす）
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        // errSecItemNotFound 等 → add
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        _ = SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func readString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    // MARK: - Tokyo DayKey

    private static func tokyoDayKey() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current

        let now = Date()
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        let d = cal.component(.day, from: now)

        let mm = String(format: "%02d", m)
        let dd = String(format: "%02d", d)
        return "\(y)-\(mm)-\(dd)"
    }
}
