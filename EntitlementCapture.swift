import Foundation

/// entitlementAtStart の生成ロジックを1箇所に固定する（SSOT）
/// - 目的：Viewごとのコピペ差分・状態の取り違え事故を根絶する
enum EntitlementCapture {

    /// PurchaseManagerの現在状態から CapturedEntitlement を生成する（唯一API）
    /// - Note: View側は entitlementAtStart をここから生成し、個別ロジックを禁止する
    @MainActor
    static func captureEntitlementAtStart(purchaseManager: PurchaseManager) -> CapturedEntitlement {
        let unlimitedState: EntitlementState = purchaseManager.realtimeAccess.isAllowed ? .active : .inactive
        let scanStatsState: EntitlementState = purchaseManager.scanStatsAccess.isAllowed ? .active : .inactive
        let kitState: EntitlementState = purchaseManager.kitAccess.isAllowed ? .active : .inactive

        return CapturedEntitlement(
            unlimitedState: unlimitedState,
            scanStatsState: scanStatsState,
            kitState: kitState
        )
    }
}
