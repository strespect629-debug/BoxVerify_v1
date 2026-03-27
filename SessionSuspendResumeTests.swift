import XCTest
@testable import BoxVerify_v1

@MainActor
final class SessionSuspendResumeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        BoxVerifyTestSupport.resetSessionManager()
        FreeTrialTestSupport.resetScanStatsTrialLimiter()
        FreeTrialTestSupport.resetKitTrialLimiter()
    }

    // MARK: - Realtime suspend / resume

    func testRealtimeSuspendAndResumeRestoresState() {
        let sessionManager = SessionManager.shared

        sessionManager.startRealtimeSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )
        XCTAssertTrue(sessionManager.setBaseCode("BASE-001"))
        sessionManager.recordRealtimeVerification(code: "BASE-001", outcome: .ok)

        XCTAssertNotNil(sessionManager.currentRealtimeSession)
        XCTAssertNil(sessionManager.suspendedSession)
        XCTAssertEqual(sessionManager.baseCode, "BASE-001")
        XCTAssertEqual(sessionManager.currentRealtimeSession?.verificationScans, 1)

        sessionManager.suspendCurrentSession(workType: .realtime)

        XCTAssertNil(sessionManager.currentRealtimeSession)
        XCTAssertNotNil(sessionManager.suspendedSession)
        XCTAssertEqual(sessionManager.baseCode, "BASE-001", "Realtime を中断しただけなら Base Code は保持される想定")

        guard let suspended = sessionManager.suspendedSession else {
            XCTFail("Realtime suspend 後に suspendedSession が存在する想定")
            return
        }

        sessionManager.resumeSuspendedSession(suspended)

        XCTAssertNil(sessionManager.suspendedSession)
        XCTAssertNotNil(sessionManager.currentRealtimeSession)
        XCTAssertEqual(sessionManager.baseCode, "BASE-001")
        XCTAssertEqual(sessionManager.currentRealtimeSession?.verificationScans, 1)
        XCTAssertEqual(sessionManager.currentRealtimeSession?.lastScannedCode, "BASE-001")
        XCTAssertEqual(sessionManager.currentRealtimeSession?.lastOutcome, .ok)
    }

    // MARK: - Kit suspend / resume

    func testKitSuspendAndResumeRestoresState() {
        let sessionManager = SessionManager.shared
        let kit = BoxVerifyTestSupport.makeKitDefinition()

        sessionManager.upsertKit(
            kitId: kit.kitId,
            requiredCounts: kit.requiredCounts
        )

        sessionManager.startKitSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )
        sessionManager.selectKitId(kit.kitId)
        _ = sessionManager.scanKitComponent("ITEM-A")

        XCTAssertNotNil(sessionManager.currentKitSession)
        XCTAssertNil(sessionManager.suspendedSession)

        sessionManager.suspendCurrentSession(workType: .kit)

        XCTAssertNil(sessionManager.currentKitSession)
        XCTAssertNotNil(sessionManager.suspendedSession)

        guard let suspended = sessionManager.suspendedSession else {
            XCTFail("Kit suspend 後に suspendedSession が存在する想定")
            return
        }

        sessionManager.resumeSuspendedSession(suspended)

        XCTAssertNil(sessionManager.suspendedSession)
        XCTAssertNotNil(sessionManager.currentKitSession)
        XCTAssertEqual(sessionManager.currentKitSession?.kitId, kit.kitId)
        XCTAssertEqual(sessionManager.currentKitSession?.scannedCounts["ITEM-A"], 1)
        XCTAssertEqual(sessionManager.currentKitSession?.requiredCounts["ITEM-A"], 2)
        XCTAssertEqual(sessionManager.currentKitSession?.requiredCounts["ITEM-B"], 1)
    }

    // MARK: - Scan Stats suspend / resume

    func testScanStatsSuspendAndResumeRestoresState() {
        let sessionManager = SessionManager.shared

        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )
        _ = sessionManager.scanStatsCount("CODE-A")
        _ = sessionManager.scanStatsCount("CODE-A")
        _ = sessionManager.scanStatsCount("CODE-B")

        XCTAssertNotNil(sessionManager.currentScanStatsSession)
        XCTAssertNil(sessionManager.suspendedSession)

        sessionManager.suspendCurrentSession(workType: .scanStats)

        XCTAssertNil(sessionManager.currentScanStatsSession)
        XCTAssertNotNil(sessionManager.suspendedSession)

        guard let suspended = sessionManager.suspendedSession else {
            XCTFail("Scan Stats suspend 後に suspendedSession が存在する想定")
            return
        }

        sessionManager.resumeSuspendedSession(suspended)

        XCTAssertNil(sessionManager.suspendedSession)
        XCTAssertNotNil(sessionManager.currentScanStatsSession)
        XCTAssertEqual(sessionManager.currentScanStatsSession?.totalScans, 3)
        XCTAssertEqual(sessionManager.currentScanStatsSession?.codeCounts["CODE-A"], 2)
        XCTAssertEqual(sessionManager.currentScanStatsSession?.codeCounts["CODE-B"], 1)
    }

    // MARK: - discard / remaining days / one-slot policy

    func testDiscardSuspendedRealtimeAlsoClearsBaseCode() {
        let sessionManager = SessionManager.shared

        sessionManager.startRealtimeSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )
        XCTAssertTrue(sessionManager.setBaseCode("BASE-001"))

        sessionManager.suspendCurrentSession(workType: .realtime)

        XCTAssertNotNil(sessionManager.suspendedSession)
        XCTAssertNil(sessionManager.currentRealtimeSession)
        XCTAssertEqual(sessionManager.baseCode, "BASE-001")

        sessionManager.discardSuspendedSession()

        XCTAssertNil(sessionManager.suspendedSession)
        XCTAssertNil(sessionManager.currentRealtimeSession)
        XCTAssertNil(sessionManager.baseCode, "Realtime 中断破棄時は Base Code も nil になる想定")
    }

    func testRemainingDaysForSuspendedSessionExistsAfterSuspend() {
        let sessionManager = SessionManager.shared

        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )
        _ = sessionManager.scanStatsCount("CODE-A")

        sessionManager.suspendCurrentSession(workType: .scanStats)

        let remaining = sessionManager.remainingDaysForSuspendedSession()

        XCTAssertNotNil(remaining)
        XCTAssertGreaterThanOrEqual(remaining ?? -1, 0)
    }

    func testOnlyOneSuspendedSessionSlotIsKeptAndRealtimeBaseCodeIsClearedWhenOverwritten() {
        let sessionManager = SessionManager.shared

        sessionManager.startRealtimeSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )
        XCTAssertTrue(sessionManager.setBaseCode("BASE-001"))
        sessionManager.suspendCurrentSession(workType: .realtime)

        let firstSuspendedId = sessionManager.suspendedSession?.id
        XCTAssertNotNil(firstSuspendedId)
        XCTAssertEqual(sessionManager.baseCode, "BASE-001", "Realtime 中断直後は Base Code を保持する想定")

        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )
        _ = sessionManager.scanStatsCount("CODE-A")
        sessionManager.suspendCurrentSession(workType: .scanStats)

        let secondSuspendedId = sessionManager.suspendedSession?.id
        XCTAssertNotNil(secondSuspendedId)
        XCTAssertNotEqual(firstSuspendedId, secondSuspendedId, "中断枠は最大1件のため、新しい中断で置き換わる想定")
        XCTAssertNil(sessionManager.baseCode, "Realtime 中断枠が他モード中断で上書きされたら Base Code は nil になる想定")

        if case .scanStats = sessionManager.suspendedSession?.payload {
            XCTAssertTrue(true)
        } else {
            XCTFail("最終的な中断枠は Scan Stats の想定")
        }
    }
}
