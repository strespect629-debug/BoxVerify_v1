import XCTest
@testable import BoxVerify_v1

@MainActor
final class WorkFlowIntegrationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        BoxVerifyTestSupport.resetSessionManager()
        FreeTrialTestSupport.resetScanStatsTrialLimiter()
        FreeTrialTestSupport.resetKitTrialLimiter()
    }

    // MARK: - Realtime workflow

    func testRealtimeWorkflow_BaseRegisterThenVerifyOK() {
        let sessionManager = SessionManager.shared

        sessionManager.startRealtimeSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        XCTAssertTrue(sessionManager.setBaseCode("BASE-001"))
        XCTAssertEqual(sessionManager.baseCode, "BASE-001")
        XCTAssertEqual(sessionManager.currentRealtimeSession?.verificationScans, 0)

        sessionManager.recordRealtimeVerification(code: "BASE-001", outcome: .ok)

        XCTAssertEqual(sessionManager.currentRealtimeSession?.verificationScans, 1)
        XCTAssertEqual(sessionManager.currentRealtimeSession?.lastScannedCode, "BASE-001")
        XCTAssertEqual(sessionManager.currentRealtimeSession?.lastOutcome, .ok)
    }

    func testRealtimeWorkflow_BaseRegisterThenVerifyNG() {
        let sessionManager = SessionManager.shared

        sessionManager.startRealtimeSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        XCTAssertTrue(sessionManager.setBaseCode("BASE-001"))

        sessionManager.recordRealtimeVerification(code: "BASE-999", outcome: .ng)

        XCTAssertEqual(sessionManager.currentRealtimeSession?.verificationScans, 1)
        XCTAssertEqual(sessionManager.currentRealtimeSession?.lastScannedCode, "BASE-999")
        XCTAssertEqual(sessionManager.currentRealtimeSession?.lastOutcome, .ng)
    }

    // MARK: - Scan Stats workflow

    func testScanStatsWorkflow_CountsAndShowsTopBreakdownOrder() {
        let sessionManager = SessionManager.shared

        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        _ = sessionManager.scanStatsCount("A")
        _ = sessionManager.scanStatsCount("B")
        _ = sessionManager.scanStatsCount("A")
        _ = sessionManager.scanStatsCount("C")
        _ = sessionManager.scanStatsCount("A")
        _ = sessionManager.scanStatsCount("B")

        guard let session = sessionManager.currentScanStatsSession else {
            XCTFail("currentScanStatsSession が存在する想定")
            return
        }

        XCTAssertEqual(session.totalScans, 6)
        XCTAssertEqual(session.codeCounts["A"], 3)
        XCTAssertEqual(session.codeCounts["B"], 2)
        XCTAssertEqual(session.codeCounts["C"], 1)

        let top = session.codeCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map(\.key)

        XCTAssertEqual(top.first, "A")
    }

    func testScanStatsWorkflow_HardLimitsRemainCorrectAfterManyCounts() {
        let sessionManager = SessionManager.shared

        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        for i in 1...10 {
            let result = sessionManager.scanStatsCount("TYPE-\(i)")
            assertScanStatsResult(result, is: .success)
        }

        let overflowType = sessionManager.scanStatsCount("TYPE-11")
        assertScanStatsResult(overflowType, is: .maxTypesReached)

        while (sessionManager.currentScanStatsSession?.totalScans ?? 0) < 1000 {
            let result = sessionManager.scanStatsCount("TYPE-1")
            assertScanStatsResult(result, is: .success)
        }

        let overflowTotal = sessionManager.scanStatsCount("TYPE-1")
        assertScanStatsResult(overflowTotal, is: .maxTotalReached)
        XCTAssertEqual(sessionManager.currentScanStatsSession?.totalScans, 1000)
    }

    // MARK: - Kit workflow

    func testKitWorkflow_SelectKitThenCompleteSuccessfully() {
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

        XCTAssertEqual(sessionManager.currentKitSession?.kitId, kit.kitId)
        XCTAssertEqual(sessionManager.currentKitSession?.requiredCounts["ITEM-A"], 2)
        XCTAssertEqual(sessionManager.currentKitSession?.requiredCounts["ITEM-B"], 1)

        assertKitOutcome(sessionManager.scanKitComponent("ITEM-A"), is: .progress)
        assertKitOutcome(sessionManager.scanKitComponent("ITEM-A"), is: .progress)
        assertKitOutcome(sessionManager.scanKitComponent("ITEM-B"), is: .completedOK)

        XCTAssertEqual(sessionManager.currentKitSession?.scannedCounts["ITEM-A"], 2)
        XCTAssertEqual(sessionManager.currentKitSession?.scannedCounts["ITEM-B"], 1)
    }

    func testKitWorkflow_UnknownCodeAndOverCountReturnNG() {
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

        let unknown = sessionManager.scanKitComponent("UNKNOWN-CODE")
        if case .completedNG(let reason) = unknown {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("未知コードは completedNG の想定")
        }

        // ITEM-B は required=1 だが、ITEM-A が未完了なので 1回目は progress
        assertKitOutcome(sessionManager.scanKitComponent("ITEM-B"), is: .progress)

        let over = sessionManager.scanKitComponent("ITEM-B")
        if case .completedNG(let reason) = over {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("必要数超過は completedNG の想定")
        }
    }

    // MARK: - Cross-mode isolation

    func testEachModeSessionIsIndependent() {
        let sessionManager = SessionManager.shared
        let kit = BoxVerifyTestSupport.makeKitDefinition()

        sessionManager.upsertKit(
            kitId: kit.kitId,
            requiredCounts: kit.requiredCounts
        )

        sessionManager.startRealtimeSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )
        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )
        sessionManager.startKitSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        XCTAssertTrue(sessionManager.setBaseCode("BASE-001"))
        sessionManager.recordRealtimeVerification(code: "BASE-001", outcome: .ok)

        _ = sessionManager.scanStatsCount("CODE-A")
        _ = sessionManager.scanStatsCount("CODE-B")

        sessionManager.selectKitId(kit.kitId)
        _ = sessionManager.scanKitComponent("ITEM-A")

        XCTAssertEqual(sessionManager.currentRealtimeSession?.verificationScans, 1)
        XCTAssertEqual(sessionManager.currentScanStatsSession?.totalScans, 2)
        XCTAssertEqual(sessionManager.currentKitSession?.scannedCounts["ITEM-A"], 1)
    }

    func testFinishingOneModeDoesNotDestroyOtherModes() {
        let sessionManager = SessionManager.shared
        let kit = BoxVerifyTestSupport.makeKitDefinition()

        sessionManager.upsertKit(
            kitId: kit.kitId,
            requiredCounts: kit.requiredCounts
        )

        sessionManager.startRealtimeSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )
        sessionManager.startScanStatsSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )
        sessionManager.startKitSessionIfNeeded(
            entitlementAtStart: BoxVerifyTestSupport.entitlement()
        )

        XCTAssertTrue(sessionManager.setBaseCode("BASE-001"))
        _ = sessionManager.scanStatsCount("CODE-A")
        sessionManager.selectKitId(kit.kitId)

        sessionManager.finishCurrentSession(workType: .scanStats)

        XCTAssertNotNil(sessionManager.currentRealtimeSession)
        XCTAssertNil(sessionManager.currentScanStatsSession)
        XCTAssertNotNil(sessionManager.currentKitSession)
        XCTAssertEqual(sessionManager.baseCode, "BASE-001")
    }

    // MARK: - Helpers

    private enum ExpectedScanStatsResult {
        case success
        case maxTypesReached
        case maxTotalReached
        case noSession
    }

    private enum ExpectedKitOutcome {
        case progress
        case completedOK
        case noSession
    }

    private func assertScanStatsResult(
        _ actual: ScanStatsCountResult,
        is expected: ExpectedScanStatsResult,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (.success, .success),
             (.maxTypesReached, .maxTypesReached),
             (.maxTotalReached, .maxTotalReached),
             (.noSession, .noSession):
            return

        default:
            XCTFail(
                message.isEmpty ? "Unexpected ScanStatsCountResult" : message,
                file: file,
                line: line
            )
        }
    }

    private func assertKitOutcome(
        _ actual: KitScanOutcome,
        is expected: ExpectedKitOutcome,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (.progress, .progress),
             (.completedOK, .completedOK),
             (.noSession, .noSession):
            return

        default:
            XCTFail(
                message.isEmpty ? "Unexpected KitScanOutcome" : message,
                file: file,
                line: line
            )
        }
    }
}
