import XCTest
import Security
@testable import BoxVerify_v1

@MainActor
enum FreeTrialTestSupport {

    // MARK: - Common

    static func resetSessionManager() {
        SessionManager.shared.resetAllStateForTesting()
    }

    static func entitlement() -> CapturedEntitlement {
        EntitlementCapture.captureEntitlementAtStart(
            purchaseManager: PurchaseManager.shared
        )
    }

    static func uniqueKitId(prefix: String = "TEST-KIT") -> String {
        "\(prefix)-\(UUID().uuidString)"
    }

    static func makeKitDefinition() -> (kitId: String, requiredCounts: [String: Int]) {
        let kitId = uniqueKitId()
        let requiredCounts: [String: Int] = [
            "ITEM-A": 2,
            "ITEM-B": 1
        ]
        return (kitId, requiredCounts)
    }

    // MARK: - Scan Stats Trial reset

    static func resetScanStatsTrialLimiter() {
        deleteKeychainValue(
            service: "com.boxverify.app.scanstats.trial",
            account: "free_preview_count"
        )
    }

    // MARK: - Kit Trial reset

    static func resetKitTrialLimiter() {
        deleteKeychainValue(
            service: "com.boxverify.app.kittrial",
            account: "one_time_result_reveal"
        )
    }

    // MARK: - Realtime Trial
    //
    // RealtimeTrialLimiter の内部保存実装がこの会話内で確定していないため、
    // ここでは自動リセットしない。
    // destructive テストとして必要時のみ走らせる。
    //

    static func shouldRunDestructiveRealtimeTrialTest() -> Bool {
        ProcessInfo.processInfo.environment["RUN_DESTRUCTIVE_REALTIME_TRIAL_TESTS"] == "1"
    }

    // MARK: - Keychain helper

    private static func deleteKeychainValue(service: String, account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
