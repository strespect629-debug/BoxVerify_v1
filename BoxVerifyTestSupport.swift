import XCTest
@testable import BoxVerify_v1

@MainActor
enum BoxVerifyTestSupport {

    static func entitlement() -> CapturedEntitlement {
        EntitlementCapture.captureEntitlementAtStart(
            purchaseManager: PurchaseManager.shared
        )
    }

    static func resetSessionManager() {
        SessionManager.shared.resetAllStateForTesting()
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
}
